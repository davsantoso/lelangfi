// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SellerRegistry.sol";
import "../src/ValidatorRegistry.sol";
import "../src/VehicleListingRegistry.sol";
import "../src/VehicleOwnershipNFT.sol";
import "../src/VehicleAuctionFactory.sol";
import "../src/VehicleAuction.sol";
import "./MockUSDC.sol";

contract SharedSetup is Test {
    uint256 public constant INITIAL_BALANCE = 1_000_000 * 1e6; // 1M USDC
    uint256 public constant COLLATERAL_BPS = 1000; // 10%
    uint256 public constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint256 public constant AUCTION_DURATION = 3 days;
    uint256 public constant START_PRICE = 10_000 * 1e6; // 10k USDC

    address public admin;
    address public seller;
    address public sellerTwo;
    address public validator;
    address public bidder1;
    address public bidder2;
    address public bidder3;
    address public treasury;

    MockUSDC public usdc;
    SellerRegistry public sellerRegistry;
    ValidatorRegistry public validatorRegistry;
    VehicleListingRegistry public listingRegistry;
    VehicleOwnershipNFT public ownershipNFT;
    VehicleAuctionFactory public factory;

    uint256 public listingId;

    function setUp() public virtual {
        admin = makeAddr("admin");
        seller = makeAddr("seller");
        sellerTwo = makeAddr("sellerTwo");
        validator = makeAddr("validator");
        bidder1 = makeAddr("bidder1");
        bidder2 = makeAddr("bidder2");
        bidder3 = makeAddr("bidder3");
        treasury = makeAddr("treasury");

        vm.startPrank(admin);

        usdc = new MockUSDC();

        sellerRegistry = new SellerRegistry(admin);
        validatorRegistry = new ValidatorRegistry(admin);

        listingRegistry = new VehicleListingRegistry(admin, address(sellerRegistry), address(validatorRegistry));

        ownershipNFT = new VehicleOwnershipNFT(admin, admin);

        factory = new VehicleAuctionFactory(
            admin,
            address(usdc),
            treasury,
            address(sellerRegistry),
            address(validatorRegistry),
            address(listingRegistry),
            address(ownershipNFT)
        );

        // Grant DEFAULT_ADMIN_ROLE to factory on NFT so it can grant MINTER_ROLE to auctions
        ownershipNFT.grantRole(ownershipNFT.DEFAULT_ADMIN_ROLE(), address(factory));

        // Authorize factory to call markListingAuctionCreated
        listingRegistry.authorizeFactory(address(factory));

        // Register seller, validator
        sellerRegistry.addSeller(seller);
        sellerRegistry.addSeller(sellerTwo);
        validatorRegistry.addValidator(validator);

        vm.stopPrank();

        // Mint USDC to bidders
        usdc.mint(bidder1, INITIAL_BALANCE);
        usdc.mint(bidder2, INITIAL_BALANCE);
        usdc.mint(bidder3, INITIAL_BALANCE);
    }

    function _submitAndApproveListing(address _seller) internal returns (uint256) {
        return _submitAndApproveListing(_seller, START_PRICE);
    }

    function _submitAndApproveListing(address _seller, uint256 startPrice) internal returns (uint256) {
        vm.prank(_seller);
        uint256 id = listingRegistry.submitListing("ipfs://test-vehicle", startPrice, COLLATERAL_BPS);

        vm.prank(validator);
        listingRegistry.approveListing(id);

        return id;
    }

    function _createAuction(uint256 id, address _seller, uint256 startPrice) internal returns (VehicleAuction) {
        vm.prank(_seller);
        address auctionAddr = factory.createAuction(id, startPrice, AUCTION_DURATION);
        return VehicleAuction(payable(auctionAddr));
    }

    function _createAuction(address _seller) internal returns (VehicleAuction) {
        uint256 id = _submitAndApproveListing(_seller);
        return _createAuction(id, _seller, START_PRICE);
    }

    function _bid(VehicleAuction auction, address bidder, uint256 amount) internal {
        uint256 collateral = (amount * COLLATERAL_BPS) / 10000;
        vm.prank(bidder);
        usdc.approve(address(auction), collateral);
        vm.prank(bidder);
        auction.placeBid(amount);
    }

    function _bidAndApprove(VehicleAuction auction, address bidder, uint256 amount) internal {
        uint256 collateral = (amount * COLLATERAL_BPS) / 10000;
        vm.prank(bidder);
        usdc.approve(address(auction), INITIAL_BALANCE);
        vm.prank(bidder);
        auction.placeBid(amount);
    }

    function _payRemaining(VehicleAuction auction, address winner, uint256 bidAmount) internal {
        uint256 collateral = (bidAmount * COLLATERAL_BPS) / 10000;
        uint256 remaining = bidAmount - collateral;
        vm.prank(winner);
        usdc.approve(address(auction), remaining);
        vm.prank(winner);
        auction.payRemaining();
    }

    function _completeHappyPath(VehicleAuction auction, address _seller, address winner, uint256 bidAmount) internal {
        _payRemaining(auction, winner, bidAmount);

        vm.prank(_seller);
        auction.confirmShipped("RESI001");

        vm.prank(winner);
        auction.confirmReceived();
    }

    function _advanceTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    function _advanceToEndTime(VehicleAuction auction) internal {
        (,,,,,,, uint256 endTime,,,) = auction.config();
        if (block.timestamp < endTime) {
            _advanceTime(endTime - block.timestamp + 1);
        }
    }
}
