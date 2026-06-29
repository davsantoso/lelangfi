// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./VehicleAuction.sol";
import "./VehicleListingRegistry.sol";
import "./SellerRegistry.sol";

contract VehicleAuctionFactory is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address public usdcToken;
    address public treasury;
    address public sellerRegistry;
    address public validatorRegistry;
    address public listingRegistry;
    address public ownershipNFT;

    uint256 public defaultMinBidIncrementBps = 500; // 5%
    uint256 public defaultCollateralBps = 1000;      // 10%
    uint256 public defaultPlatformFeeBps = 250;       // 2.5%
    uint256 public defaultDuration = 3 days;

    uint256 public auctionCounter;
    mapping(uint256 => address) public auctionByListing;
    address[] public allAuctions;

    event AuctionCreated(uint256 indexed listingId, address auctionAddress, uint256 startPrice, uint256 endTime);
    event FactoryConfigUpdated(string param);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "VehicleAuctionFactory: only admin");
        _;
    }

    constructor(
        address admin,
        address _usdcToken,
        address _treasury,
        address _sellerRegistry,
        address _validatorRegistry,
        address _listingRegistry,
        address _ownershipNFT
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        usdcToken = _usdcToken;
        treasury = _treasury;
        sellerRegistry = _sellerRegistry;
        validatorRegistry = _validatorRegistry;
        listingRegistry = _listingRegistry;
        ownershipNFT = _ownershipNFT;
    }

    function createAuction(
        uint256 listingId,
        uint256 startPrice,
        uint256 duration
    ) external returns (address) {
        VehicleListingRegistry vlr = VehicleListingRegistry(listingRegistry);
        Listing memory listing = vlr.getListing(listingId);

        require(listing.id == listingId, "VehicleAuctionFactory: listing not found");
        require(listing.seller == msg.sender, "VehicleAuctionFactory: not listing owner");
        require(listing.status == ListingStatus.APPROVED, "VehicleAuctionFactory: listing not approved");
        require(auctionByListing[listingId] == address(0), "VehicleAuctionFactory: auction already exists");

        require(startPrice > 0, "VehicleAuctionFactory: zero start price");
        require(duration > 0, "VehicleAuctionFactory: zero duration");

        // Grant MINTER_ROLE to the new auction on the NFT contract
        VehicleOwnershipNFT nft = VehicleOwnershipNFT(ownershipNFT);

        // Deploy new auction contract
        VehicleAuction auction = new VehicleAuction(
            address(this),
            msg.sender,
            listingId,
            usdcToken,
            treasury,
            sellerRegistry,
            validatorRegistry,
            listingRegistry,
            ownershipNFT,
            startPrice,
            duration,
            defaultMinBidIncrementBps,
            defaultCollateralBps,
            defaultPlatformFeeBps
        );

        address auctionAddress = address(auction);
        auctionByListing[listingId] = auctionAddress;
        allAuctions.push(auctionAddress);

        // Grant MINTER_ROLE to the auction so it can mint NFTs
        nft.grantRole(nft.MINTER_ROLE(), auctionAddress);

        // Mark listing as auction created
        vlr.markListingAuctionCreated(listingId);

        emit AuctionCreated(listingId, auctionAddress, startPrice, block.timestamp + duration);

        return auctionAddress;
    }

    // ── Admin Config ──

    function setUsdcToken(address _usdcToken) external onlyAdmin {
        usdcToken = _usdcToken;
        emit FactoryConfigUpdated("usdcToken");
    }

    function setTreasury(address _treasury) external onlyAdmin {
        treasury = _treasury;
        emit FactoryConfigUpdated("treasury");
    }

    function setDefaultMinBidIncrementBps(uint256 _bps) external onlyAdmin {
        require(_bps > 0 && _bps <= 2000, "VehicleAuctionFactory: invalid bps");
        defaultMinBidIncrementBps = _bps;
        emit FactoryConfigUpdated("minBidIncrementBps");
    }

    function setDefaultCollateralBps(uint256 _bps) external onlyAdmin {
        require(_bps > 0 && _bps <= 2000, "VehicleAuctionFactory: invalid bps");
        defaultCollateralBps = _bps;
        emit FactoryConfigUpdated("collateralBps");
    }

    function setDefaultPlatformFeeBps(uint256 _bps) external onlyAdmin {
        require(_bps <= 1000, "VehicleAuctionFactory: fee too high");
        defaultPlatformFeeBps = _bps;
        emit FactoryConfigUpdated("platformFeeBps");
    }

    function setDefaultDuration(uint256 _duration) external onlyAdmin {
        require(_duration > 0, "VehicleAuctionFactory: zero duration");
        defaultDuration = _duration;
        emit FactoryConfigUpdated("duration");
    }

    function updateAuctionTreasury(address auctionAddress) external onlyAdmin {
        VehicleAuction auction = VehicleAuction(auctionAddress);
        auction.setTreasury(treasury);
    }

    // ── Getters ──

    function getAuctions() external view returns (address[] memory) {
        return allAuctions;
    }

    function getAuctionCount() external view returns (uint256) {
        return allAuctions.length;
    }

    function getAuctionByListing(uint256 listingId) external view returns (address) {
        return auctionByListing[listingId];
    }
}
