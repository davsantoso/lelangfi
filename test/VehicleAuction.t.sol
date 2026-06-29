// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SharedSetup.sol";

contract VehicleAuctionTest is SharedSetup {
    VehicleAuction public auction;
    uint256 public winningBid;

    function setUp() public override {
        super.setUp();
        listingId = _submitAndApproveListing(seller);
        auction = _createAuction(listingId, seller, START_PRICE);
        winningBid = START_PRICE;
    }

    // ── Happy Path ──

    function test_HappyPath_BidPayConfirm() public {
        _bid(auction, bidder1, START_PRICE);

        uint256 sellerBalBefore = usdc.balanceOf(seller);
        uint256 bidderBalBefore = usdc.balanceOf(bidder1);
        uint256 treasuryBalBefore = usdc.balanceOf(treasury);

        _advanceToEndTime(auction);
        auction.startPaymentPhase();
        _completeHappyPath(auction, seller, bidder1, START_PRICE);

        uint256 expectedCollateral = (START_PRICE * COLLATERAL_BPS) / 10000;
        uint256 expectedFee = (START_PRICE * PLATFORM_FEE_BPS) / 10000;
        uint256 expectedSeller = START_PRICE - expectedCollateral - expectedFee;

        assertEq(usdc.balanceOf(seller), sellerBalBefore + expectedSeller, "seller balance");
        assertEq(usdc.balanceOf(bidder1), bidderBalBefore - START_PRICE + expectedCollateral * 2, "bidder balance");
        assertEq(usdc.balanceOf(treasury), treasuryBalBefore + expectedFee, "treasury balance");
    }

    // ── Soulbound NFT ──

    function test_NFT_MintedAndSoulbound() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);
        auction.startPaymentPhase();
        _payRemaining(auction, bidder1, START_PRICE);

        uint256 tokenId = ownershipNFT.buyerTokenId(bidder1);
        assertTrue(tokenId != 0, "token should be minted");
        assertEq(ownershipNFT.ownerOf(tokenId), bidder1, "owner should be bidder");

        vm.prank(bidder1);
        vm.expectRevert("VehicleOwnershipNFT: not transferable yet");
        ownershipNFT.transferFrom(bidder1, address(0x456), tokenId);
    }

    function test_NFT_TransferableAfterCompletion() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);
        auction.startPaymentPhase();
        _completeHappyPath(auction, seller, bidder1, START_PRICE);

        uint256 tokenId = ownershipNFT.buyerTokenId(bidder1);

        vm.prank(bidder1);
        ownershipNFT.transferFrom(bidder1, address(0x456), tokenId);

        assertEq(ownershipNFT.ownerOf(tokenId), address(0x456));
    }

    // ── Anti-snipe ──

    function test_AntiSnipe_ExtendsEndTime() public {
        _bid(auction, bidder1, START_PRICE);

        uint256 endTimeBefore = _getEndTime();

        _advanceTime(endTimeBefore - block.timestamp - 5 minutes);

        _bid(auction, bidder2, START_PRICE * 105 / 100);

        uint256 endTimeAfter = _getEndTime();

        assertEq(endTimeAfter, endTimeBefore + 10 minutes, "end time should extend by 10 min");
    }

    function test_AntiSnipe_NoExtensionIfEarly() public {
        _bid(auction, bidder1, START_PRICE);

        uint256 endTimeBefore = _getEndTime();

        _bid(auction, bidder2, START_PRICE * 105 / 100);

        uint256 endTimeAfter = _getEndTime();

        assertEq(endTimeAfter, endTimeBefore, "end time should not change");
    }

    function _getEndTime() internal view returns (uint256) {
        (,,,,,,, uint256 endTime,,,) = auction.config();
        return endTime;
    }

    // ── Access Control ──

    function test_SellerCannotBid() public {
        vm.prank(seller);
        vm.expectRevert("VehicleAuction: seller cannot bid");
        auction.placeBid(START_PRICE);
    }

    function test_NonHighestBidderCanCancel() public {
        _bid(auction, bidder1, START_PRICE);
        _bid(auction, bidder2, START_PRICE * 105 / 100);

        uint256 collat = (START_PRICE * COLLATERAL_BPS) / 10000;
        uint256 balBefore = usdc.balanceOf(bidder1);

        vm.prank(bidder1);
        auction.cancelBid();

        assertEq(usdc.balanceOf(bidder1), balBefore + collat, "collateral returned");
    }

    function test_HighestBidderCannotCancel() public {
        _bid(auction, bidder1, START_PRICE);

        vm.prank(bidder1);
        vm.expectRevert("VehicleAuction: highest bidder cannot cancel");
        auction.cancelBid();
    }

    function test_BidRequiresMinIncrement() public {
        _bid(auction, bidder1, START_PRICE);

        vm.prank(bidder2);
        vm.expectRevert("VehicleAuction: below minimum increment");
        auction.placeBid(START_PRICE);
    }

    function test_EveryoneCanStartPaymentPhase() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);

        vm.prank(bidder3);
        auction.startPaymentPhase();

        assertEq(uint256(_getStatus()), uint256(AuctionStatus.AWAITING_PAYMENT));
    }

    function test_OnlySellerCanConfirmShipped() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);
        auction.startPaymentPhase();
        _payRemaining(auction, bidder1, START_PRICE);

        vm.prank(bidder1);
        vm.expectRevert("VehicleAuction: only seller");
        auction.confirmShipped("RESI");
    }

    function test_OnlyBuyerCanConfirmReceived() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);
        auction.startPaymentPhase();
        _payRemaining(auction, bidder1, START_PRICE);

        vm.prank(seller);
        auction.confirmShipped("RESI");

        vm.prank(bidder2);
        vm.expectRevert("VehicleAuction: not NFT holder");
        auction.confirmReceived();
    }

    // ── Multiple Bidders ──

    function test_MultipleBidders() public {
        _bid(auction, bidder1, START_PRICE);
        _bid(auction, bidder2, START_PRICE * 110 / 100);
        _bid(auction, bidder3, START_PRICE * 12 / 10);

        assertEq(auction.getBidCount(), 3);
    }

    // ── Edge Cases ──

    function test_StartPaymentPhase_NoBids_Cancels() public {
        _advanceToEndTime(auction);
        auction.startPaymentPhase();

        assertEq(uint256(_getStatus()), uint256(AuctionStatus.CANCELLED));
    }

    function test_Bid_BelowStartPrice_Reverts() public {
        vm.prank(bidder1);
        vm.expectRevert("VehicleAuction: below start price");
        auction.placeBid(START_PRICE - 1);
    }

    function test_PayRemaining_BeforeDeadline() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);
        auction.startPaymentPhase();

        _payRemaining(auction, bidder1, START_PRICE);

        assertEq(uint256(_getStatus()), uint256(AuctionStatus.AWAITING_DELIVERY));
    }

    function test_Dispute_BuyerFault_DanaKeSeller() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);
        auction.startPaymentPhase();
        _payRemaining(auction, bidder1, START_PRICE);

        vm.prank(seller);
        auction.confirmShipped("RESI001");

        _advanceTime(15 days);

        auction.requestDisputeResolution();

        uint256 sellerBalBefore = usdc.balanceOf(seller);
        uint256 treasuryBalBefore = usdc.balanceOf(treasury);

        vm.prank(validator);
        auction.resolveDispute(true);

        uint256 expectedCollateral = (START_PRICE * COLLATERAL_BPS) / 10000;
        uint256 expectedFee = (START_PRICE * PLATFORM_FEE_BPS) / 10000;
        uint256 expectedSeller = START_PRICE - expectedCollateral - expectedFee;

        assertEq(usdc.balanceOf(seller), sellerBalBefore + expectedSeller, "seller should be paid");
        assertEq(usdc.balanceOf(treasury), treasuryBalBefore + expectedFee, "treasury gets fee");
    }

    function test_Dispute_SellerFault_RefundBuyer() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);
        auction.startPaymentPhase();
        _payRemaining(auction, bidder1, START_PRICE);

        vm.prank(seller);
        auction.confirmShipped("RESI001");

        _advanceTime(15 days);

        auction.requestDisputeResolution();

        uint256 bidderBalBefore = usdc.balanceOf(bidder1);

        vm.prank(validator);
        auction.resolveDispute(false);

        assertEq(usdc.balanceOf(bidder1), bidderBalBefore + START_PRICE, "buyer refunded");
    }

    function test_Dispute_SellerFault_NFTBurned() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);
        auction.startPaymentPhase();
        _payRemaining(auction, bidder1, START_PRICE);

        uint256 tokenId = ownershipNFT.buyerTokenId(bidder1);

        vm.prank(seller);
        auction.confirmShipped("RESI001");

        _advanceTime(15 days);

        auction.requestDisputeResolution();

        vm.prank(validator);
        auction.resolveDispute(false);

        vm.expectRevert();
        ownershipNFT.ownerOf(tokenId);
    }

    function test_Dispute_OnlyValidator() public {
        _bid(auction, bidder1, START_PRICE);
        _advanceToEndTime(auction);
        auction.startPaymentPhase();
        _payRemaining(auction, bidder1, START_PRICE);

        vm.prank(seller);
        auction.confirmShipped("RESI");

        _advanceTime(15 days);
        auction.requestDisputeResolution();

        vm.prank(seller);
        vm.expectRevert("VehicleAuction: only validator");
        auction.resolveDispute(true);
    }

    function _getStatus() internal view returns (AuctionStatus) {
        (,,,,,,,,,, AuctionStatus status) = auction.config();
        return status;
    }
}
