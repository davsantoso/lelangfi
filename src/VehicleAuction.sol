// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./VehicleOwnershipNFT.sol";
import "./VehicleListingRegistry.sol";
import "./ValidatorRegistry.sol";

enum AuctionStatus {
    OPEN,
    ENDED,
    AWAITING_PAYMENT,
    AWAITING_DELIVERY,
    IN_DELIVERY,
    IN_DISPUTE,
    COMPLETED,
    CANCELLED
}

struct Bid {
    address bidder;
    uint256 bidAmount;
    uint256 collateral;
    uint256 timestamp;
    bool active;
}

struct AuctionConfig {
    address seller;
    uint256 listingId;
    address usdcToken;
    uint256 startPrice;
    uint256 minBidIncrementBps;
    uint256 collateralBps;
    uint256 platformFeeBps;
    uint256 endTime;
    uint256 paymentDeadline;
    uint256 currentOfferIndex;
    AuctionStatus status;
}

contract VehicleAuction is ReentrancyGuard {
    AuctionConfig public config;
    Bid[] public bids;
    uint256 public highestBidIndex;

    address public factory;
    address public treasury;
    address public sellerRegistry;
    address public validatorRegistry;
    address public listingRegistry;
    VehicleOwnershipNFT public ownershipNFT;

    uint256 public disputeRequestTime;
    string public trackingInfo;

    uint256 public constant EXTEND_WINDOW = 10 minutes;
    uint256 public constant EXTEND_DURATION = 10 minutes;
    uint256 public constant PAYMENT_WINDOW = 3 days;
    uint256 public constant DISPUTE_WINDOW = 14 days;
    uint256 public constant MAX_BPS = 10000;

    event BidPlaced(address indexed bidder, uint256 bidAmount, uint256 collateral, uint256 newEndTime);
    event BidCancelled(address indexed bidder, uint256 collateralReturned);
    event AuctionEnded(address indexed winner, uint256 winningBid);
    event PaymentOfferSent(address indexed bidder, uint256 bidAmount, uint256 deadline);
    event PaymentCompleted(address indexed buyer, uint256 totalPaid);
    event OwnershipNFTMinted(address indexed buyer, uint256 tokenId);
    event ShipmentConfirmed(address indexed seller, string trackingInfo);
    event DeliveryConfirmed(address indexed buyer, uint256 sellerReceived, uint256 feeCollected);
    event CollateralSlashed(address indexed bidder, uint256 amount);
    event OfferDeclined(address indexed bidder);
    event DisputeOpened();
    event DisputeResolved(bool buyerFault, address indexed resolvedBy);
    event AuctionCancelled(uint256 indexed listingId);

    modifier onlySeller() {
        require(msg.sender == config.seller, "VehicleAuction: only seller");
        _;
    }

    modifier onlyValidator() {
        ValidatorRegistry vr = ValidatorRegistry(validatorRegistry);
        require(vr.isWhitelistedValidator(msg.sender), "VehicleAuction: only validator");
        _;
    }

    modifier inStatus(AuctionStatus s) {
        require(config.status == s, "VehicleAuction: invalid status");
        _;
    }

    constructor(
        address _factory,
        address _seller,
        uint256 _listingId,
        address _usdcToken,
        address _treasury,
        address _sellerRegistry,
        address _validatorRegistry,
        address _listingRegistry,
        address _ownershipNFT,
        uint256 _startPrice,
        uint256 _duration,
        uint256 _minBidIncrementBps,
        uint256 _collateralBps,
        uint256 _platformFeeBps
    ) {
        factory = _factory;
        config = AuctionConfig({
            seller: _seller,
            listingId: _listingId,
            usdcToken: _usdcToken,
            startPrice: _startPrice,
            minBidIncrementBps: _minBidIncrementBps,
            collateralBps: _collateralBps,
            platformFeeBps: _platformFeeBps,
            endTime: block.timestamp + _duration,
            paymentDeadline: 0,
            currentOfferIndex: type(uint256).max,
            status: AuctionStatus.OPEN
        });
        treasury = _treasury;
        sellerRegistry = _sellerRegistry;
        validatorRegistry = _validatorRegistry;
        listingRegistry = _listingRegistry;
        ownershipNFT = VehicleOwnershipNFT(_ownershipNFT);
    }

    // ── Phase 2: Bidding ──

    function placeBid(uint256 bidAmount) external nonReentrant inStatus(AuctionStatus.OPEN) {
        require(bidAmount >= config.startPrice, "VehicleAuction: below start price");
        require(msg.sender != config.seller, "VehicleAuction: seller cannot bid");
        require(bidAmount > 0, "VehicleAuction: zero bid");

        if (bids.length > 0) {
            Bid memory highest = bids[highestBidIndex];
            uint256 minBid = (highest.bidAmount * (MAX_BPS + config.minBidIncrementBps)) / MAX_BPS;
            require(bidAmount >= minBid, "VehicleAuction: below minimum increment");
        }

        uint256 collateral = (bidAmount * config.collateralBps) / MAX_BPS;

        IERC20 usdc = IERC20(config.usdcToken);
        require(usdc.transferFrom(msg.sender, address(this), collateral), "VehicleAuction: collateral transfer failed");

        uint256 newEndTime = config.endTime;
        if (block.timestamp + EXTEND_WINDOW >= config.endTime) {
            newEndTime = config.endTime + EXTEND_DURATION;
        }

        bids.push(Bid({
            bidder: msg.sender,
            bidAmount: bidAmount,
            collateral: collateral,
            timestamp: block.timestamp,
            active: true
        }));

        uint256 bidIndex = bids.length - 1;
        if (bids.length == 1 || bidAmount > bids[highestBidIndex].bidAmount) {
            highestBidIndex = bidIndex;
        }

        config.endTime = newEndTime;

        emit BidPlaced(msg.sender, bidAmount, collateral, newEndTime);
    }

    function cancelBid() external nonReentrant {
        require(
            config.status == AuctionStatus.OPEN || config.status == AuctionStatus.ENDED,
            "VehicleAuction: cannot cancel in current status"
        );

        (uint256 bidIndex,) = _findActiveBid(msg.sender);
        require(bidIndex != type(uint256).max, "VehicleAuction: no active bid found");
        require(bidIndex != highestBidIndex, "VehicleAuction: highest bidder cannot cancel");

        bids[bidIndex].active = false;
        uint256 collateral = bids[bidIndex].collateral;

        require(IERC20(config.usdcToken).transfer(msg.sender, collateral), "VehicleAuction: transfer failed");

        emit BidCancelled(msg.sender, collateral);
    }

    function _findActiveBid(address bidder) internal view returns (uint256 index, uint256 count) {
        index = type(uint256).max;
        count = 0;

        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].active) {
                if (bids[i].bidder == bidder) {
                    index = i;
                }
                count++;
            }
        }
    }

    // ── Phase 3: Payment ──

    function startPaymentPhase() external nonReentrant {
        require(
            config.status == AuctionStatus.OPEN || config.status == AuctionStatus.ENDED,
            "VehicleAuction: auction not ended"
        );
        require(block.timestamp >= config.endTime, "VehicleAuction: auction still open");

        if (config.status == AuctionStatus.OPEN) {
            config.status = AuctionStatus.ENDED;
        }

        uint256 highestActive = _findHighestActiveBid();
        if (highestActive == type(uint256).max) {
            config.status = AuctionStatus.CANCELLED;
            _returnAllCollateral();
            emit AuctionCancelled(config.listingId);
            return;
        }

        emit AuctionEnded(bids[highestActive].bidder, bids[highestActive].bidAmount);

        _sendOffer(highestActive);
    }

    function _sendOffer(uint256 bidIndex) internal {
        config.currentOfferIndex = bidIndex;
        config.paymentDeadline = block.timestamp + PAYMENT_WINDOW;
        config.status = AuctionStatus.AWAITING_PAYMENT;

        emit PaymentOfferSent(bids[bidIndex].bidder, bids[bidIndex].bidAmount, config.paymentDeadline);
    }

    function payRemaining() external nonReentrant inStatus(AuctionStatus.AWAITING_PAYMENT) {
        require(config.currentOfferIndex < bids.length, "VehicleAuction: no current offer");
        Bid storage currentBid = bids[config.currentOfferIndex];
        require(msg.sender == currentBid.bidder, "VehicleAuction: not current offer recipient");
        require(block.timestamp <= config.paymentDeadline, "VehicleAuction: payment deadline passed");
        require(currentBid.active, "VehicleAuction: bid not active");

        uint256 remaining = currentBid.bidAmount - currentBid.collateral;

        IERC20 usdc = IERC20(config.usdcToken);
        require(usdc.transferFrom(msg.sender, address(this), remaining), "VehicleAuction: payment transfer failed");

        config.status = AuctionStatus.AWAITING_DELIVERY;

        emit PaymentCompleted(msg.sender, currentBid.bidAmount);

        // Mint ownership NFT
        VehicleListingRegistry vlr = VehicleListingRegistry(listingRegistry);
        Listing memory listingData = vlr.getListing(config.listingId);

        uint256 tokenId = ownershipNFT.mint(
            msg.sender,
            config.listingId,
            listingData.vehicleMetadataHash,
            address(this),
            currentBid.bidAmount
        );

        emit OwnershipNFTMinted(msg.sender, tokenId);
    }

    // ── Cascading Offer ──

    function acceptOffer() external nonReentrant inStatus(AuctionStatus.AWAITING_PAYMENT) {
        require(config.currentOfferIndex < bids.length, "VehicleAuction: no current offer");
        Bid storage currentBid = bids[config.currentOfferIndex];
        require(msg.sender == currentBid.bidder, "VehicleAuction: not current offer recipient");
        require(block.timestamp <= config.paymentDeadline, "VehicleAuction: deadline passed");
        require(currentBid.active, "VehicleAuction: bid not active");

        // Accept is implicit — bidder must still call payRemaining()
        // This function exists for explicit confirmation
    }

    function declineOffer() external nonReentrant inStatus(AuctionStatus.AWAITING_PAYMENT) {
        require(config.currentOfferIndex < bids.length, "VehicleAuction: no current offer");
        Bid storage currentBid = bids[config.currentOfferIndex];
        require(msg.sender == currentBid.bidder, "VehicleAuction: not current offer recipient");
        require(block.timestamp <= config.paymentDeadline, "VehicleAuction: deadline passed");
        require(currentBid.active, "VehicleAuction: bid not active");

        currentBid.active = false;

        require(IERC20(config.usdcToken).transfer(msg.sender, currentBid.collateral), "VehicleAuction: transfer failed");

        emit OfferDeclined(msg.sender);

        _advanceToNextOffer();
    }

    function slashAndOfferNext() external nonReentrant inStatus(AuctionStatus.AWAITING_PAYMENT) {
        require(config.currentOfferIndex < bids.length, "VehicleAuction: no current offer");
        require(block.timestamp > config.paymentDeadline, "VehicleAuction: deadline not passed");

        Bid storage currentBid = bids[config.currentOfferIndex];
        if (currentBid.active) {
            currentBid.active = false;

            // Slash collateral to treasury
            require(IERC20(config.usdcToken).transfer(treasury, currentBid.collateral), "VehicleAuction: transfer failed");

            emit CollateralSlashed(currentBid.bidder, currentBid.collateral);
        }

        _advanceToNextOffer();
    }

    function _advanceToNextOffer() internal {
        uint256 nextIndex = _findNextHighestActiveBid();
        if (nextIndex == type(uint256).max) {
            config.status = AuctionStatus.CANCELLED;
            _returnAllCollateral();
            emit AuctionCancelled(config.listingId);
        } else {
            _sendOffer(nextIndex);
        }
    }

    function _findHighestActiveBid() internal view returns (uint256) {
        uint256 highest = 0;
        uint256 highestIndex = type(uint256).max;

        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].active && bids[i].bidAmount > highest) {
                highest = bids[i].bidAmount;
                highestIndex = i;
            }
        }

        return highestIndex;
    }

    function _findNextHighestActiveBid() internal view returns (uint256) {
        uint256 highest = 0;
        uint256 highestIndex = type(uint256).max;

        for (uint256 i = 0; i < bids.length; i++) {
            if (i == config.currentOfferIndex) continue;
            if (bids[i].active && bids[i].bidAmount > highest) {
                highest = bids[i].bidAmount;
                highestIndex = i;
            }
        }

        return highestIndex;
    }

    function _returnAllCollateral() internal {
        IERC20 usdc = IERC20(config.usdcToken);
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].active) {
                bids[i].active = false;
                uint256 collateral = bids[i].collateral;
                if (collateral > 0) {
                    require(usdc.transfer(bids[i].bidder, collateral), "VehicleAuction: transfer failed");
                }
            }
        }
    }

    // ── Phase 4: Delivery ──

    function confirmShipped(string calldata _trackingInfo) external nonReentrant onlySeller inStatus(AuctionStatus.AWAITING_DELIVERY) {
        trackingInfo = _trackingInfo;
        disputeRequestTime = block.timestamp;
        config.status = AuctionStatus.IN_DELIVERY;

        emit ShipmentConfirmed(msg.sender, _trackingInfo);
    }

    function confirmReceived() external nonReentrant inStatus(AuctionStatus.IN_DELIVERY) {
        uint256 tokenId = ownershipNFT.buyerTokenId(msg.sender);
        require(tokenId != 0, "VehicleAuction: not NFT holder");
        require(ownershipNFT.ownerOf(tokenId) == msg.sender, "VehicleAuction: not token owner");

        _releaseFunds();

        config.status = AuctionStatus.COMPLETED;

        // Make NFT transferable
        ownershipNFT.setTransferable(tokenId, true);
    }

    function _releaseFunds() internal {
        Bid storage winningBid = bids[config.currentOfferIndex];
        uint256 totalAmount = winningBid.bidAmount;
        uint256 collateral = winningBid.collateral;

        IERC20 usdc = IERC20(config.usdcToken);

        require(usdc.transfer(msg.sender, collateral), "VehicleAuction: transfer failed");

        uint256 fee = (totalAmount * config.platformFeeBps) / MAX_BPS;
        require(usdc.transfer(treasury, fee), "VehicleAuction: transfer failed");

        uint256 sellerAmount = totalAmount - collateral - fee;
        require(usdc.transfer(config.seller, sellerAmount), "VehicleAuction: transfer failed");

        emit DeliveryConfirmed(msg.sender, sellerAmount, fee);
    }

    // ── Phase 5: Dispute ──

    function requestDisputeResolution() external nonReentrant inStatus(AuctionStatus.IN_DELIVERY) {
        require(block.timestamp >= disputeRequestTime + DISPUTE_WINDOW, "VehicleAuction: dispute window not reached");

        config.status = AuctionStatus.IN_DISPUTE;

        emit DisputeOpened();
    }

    function resolveDispute(bool buyerFault) external nonReentrant onlyValidator inStatus(AuctionStatus.IN_DISPUTE) {
        Bid storage winningBid = bids[config.currentOfferIndex];
        IERC20 usdc = IERC20(config.usdcToken);

        if (buyerFault) {
            // Release funds to seller as if confirmReceived was called
            uint256 totalAmount = winningBid.bidAmount;
            uint256 collateral = winningBid.collateral;
            uint256 fee = (totalAmount * config.platformFeeBps) / MAX_BPS;
            uint256 sellerAmount = totalAmount - collateral - fee;

            require(usdc.transfer(winningBid.bidder, collateral), "VehicleAuction: transfer failed");
            require(usdc.transfer(treasury, fee), "VehicleAuction: transfer failed");
            require(usdc.transfer(config.seller, sellerAmount), "VehicleAuction: transfer failed");
            config.status = AuctionStatus.COMPLETED;

            // Get the tokenId and make it transferable
            uint256 tokenId = _findBuyerTokenId();
            if (tokenId != 0) {
                ownershipNFT.setTransferable(tokenId, true);
            }
        } else {
            // Mark winning bid inactive so _returnAllCollateral doesn't double-pay
            winningBid.active = false;

            // Refund buyer full bidAmount (includes collateral + payment)
            uint256 totalAmount = winningBid.bidAmount;
            require(usdc.transfer(winningBid.bidder, totalAmount), "VehicleAuction: transfer failed");

            uint256 tokenId = _findBuyerTokenId();
            if (tokenId != 0) {
                ownershipNFT.burn(tokenId);
            }

            // Return all other active bids' collateral
            _returnAllCollateral();

            config.status = AuctionStatus.CANCELLED;
        }

        emit DisputeResolved(buyerFault, msg.sender);
    }

    function _findBuyerTokenId() internal view returns (uint256) {
        Bid storage winningBid = bids[config.currentOfferIndex];
        return ownershipNFT.buyerTokenId(winningBid.bidder);
    }

    // ── Admin ──

    function setTreasury(address _treasury) external {
        require(msg.sender == factory, "VehicleAuction: only factory");
        treasury = _treasury;
    }

    function setPlatformFeeBps(uint256 _platformFeeBps) external {
        require(msg.sender == factory, "VehicleAuction: only factory");
        require(_platformFeeBps <= 1000, "VehicleAuction: fee too high");
        config.platformFeeBps = _platformFeeBps;
    }

    // ── Getters ──

    function getBids() external view returns (Bid[] memory) {
        return bids;
    }

    function getBidCount() external view returns (uint256) {
        return bids.length;
    }

    function getCurrentOffer() external view returns (Bid memory) {
        if (config.currentOfferIndex < bids.length) {
            return bids[config.currentOfferIndex];
        }
        revert("VehicleAuction: no current offer");
    }
}
