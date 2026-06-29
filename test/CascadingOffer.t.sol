// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SharedSetup.sol";

contract CascadingOfferTest is SharedSetup {
    VehicleAuction public auction;

    uint256 public bid1Amount;
    uint256 public bid2Amount;
    uint256 public bid3Amount;

    function setUp() public override {
        super.setUp();

        listingId = _submitAndApproveListing(seller);
        auction = _createAuction(listingId, seller, START_PRICE);

        bid1Amount = START_PRICE * 12 / 10; // 12000
        bid2Amount = START_PRICE * 11 / 10; // 11000
        bid3Amount = START_PRICE; // 10000

        // Place bids in increasing order
        _bid(auction, bidder3, bid3Amount);
        _bid(auction, bidder2, bid2Amount);
        _bid(auction, bidder1, bid1Amount);

        _advanceToEndTime(auction);
        auction.startPaymentPhase();
    }

    // ── Winner Kabur → Cascade ke Bidder-2 ──

    function test_WinnerKabur_CascadeToBidder2() public {
        _advanceTime(4 days);

        auction.slashAndOfferNext();

        Bid memory offer = auction.getCurrentOffer();
        assertEq(offer.bidder, bidder2, "offer should go to bidder2");
        assertTrue(offer.active, "bid should be active");

        _payRemaining(auction, bidder2, bid2Amount);

        vm.prank(seller);
        auction.confirmShipped("RESI");

        vm.prank(bidder2);
        auction.confirmReceived();

        assertEq(uint256(_getStatus()), uint256(AuctionStatus.COMPLETED));
    }

    // ── Winner Kabur → Slash Collateral → Treasury ──

    function test_WinnerKabur_CollateralSlashed() public {
        uint256 treasuryBalBefore = usdc.balanceOf(treasury);
        uint256 bidder1Collateral = (bid1Amount * COLLATERAL_BPS) / 10000;

        _advanceTime(4 days);

        auction.slashAndOfferNext();

        assertEq(usdc.balanceOf(treasury), treasuryBalBefore + bidder1Collateral, "slashed collateral to treasury");
    }

    // ── Bidder-2 Decline → Cascade ke Bidder-3 ──

    function test_Bidder2Decline_CascadeToBidder3() public {
        _advanceTime(4 days);
        auction.slashAndOfferNext();

        vm.prank(bidder2);
        auction.declineOffer();

        Bid memory offer = auction.getCurrentOffer();
        assertEq(offer.bidder, bidder3, "offer should go to bidder3");
        assertTrue(offer.active, "bid should be active");
    }

    // ── Bidder-2 Decline → Collateral Kembali ──

    function test_Bidder2Decline_CollateralReturned() public {
        _advanceTime(4 days);
        auction.slashAndOfferNext();

        uint256 bidder2Collateral = (bid2Amount * COLLATERAL_BPS) / 10000;
        uint256 balBefore = usdc.balanceOf(bidder2);

        vm.prank(bidder2);
        auction.declineOffer();

        assertEq(usdc.balanceOf(bidder2), balBefore + bidder2Collateral, "collateral returned");
    }

    // ── Semua Bidder Kabur → Auction CANCELLED ──

    function test_AllBiddersKabur_AuctionCancelled() public {
        _advanceTime(4 days);
        auction.slashAndOfferNext();

        _advanceTime(4 days);
        auction.slashAndOfferNext();

        _advanceTime(4 days);
        auction.slashAndOfferNext();

        assertEq(uint256(_getStatus()), uint256(AuctionStatus.CANCELLED));
    }

    // ── Semua Bidder Decline → Auction CANCELLED ──

    function test_AllBiddersDecline_AuctionCancelled() public {
        _advanceTime(4 days);
        auction.slashAndOfferNext();

        vm.prank(bidder2);
        auction.declineOffer();

        vm.prank(bidder3);
        auction.declineOffer();

        assertEq(uint256(_getStatus()), uint256(AuctionStatus.CANCELLED));
    }

    // ── Semua Decline → Collateral Kembali ke Bidder Aktif ──

    function test_AllDecline_CollateralReturned() public {
        _advanceTime(4 days);
        auction.slashAndOfferNext();

        uint256 bidder3Collateral = (bid3Amount * COLLATERAL_BPS) / 10000;
        uint256 b3Before = usdc.balanceOf(bidder3);

        vm.prank(bidder2);
        auction.declineOffer();

        vm.prank(bidder3);
        auction.declineOffer();

        assertEq(usdc.balanceOf(bidder3), b3Before + bidder3Collateral, "bidder3 collateral returned");
    }

    // ── Bidder-3 Accept & Pay → Happy Cascade ──

    function test_Bidder3AcceptsAndPays() public {
        _advanceTime(4 days);
        auction.slashAndOfferNext();

        vm.prank(bidder2);
        auction.declineOffer();

        _payRemaining(auction, bidder3, bid3Amount);

        vm.prank(seller);
        auction.confirmShipped("RESI3");

        vm.prank(bidder3);
        auction.confirmReceived();

        assertEq(uint256(_getStatus()), uint256(AuctionStatus.COMPLETED));
    }

    // ── Cannot slash before deadline ──

    function test_CannotSlashBeforeDeadline() public {
        _advanceTime(1 days);

        vm.expectRevert("VehicleAuction: deadline not passed");
        auction.slashAndOfferNext();
    }

    // ── Bidder-2 yang tidak respons kena slash ──

    function test_Bidder2NotResponding_Slashed() public {
        _advanceTime(4 days);
        auction.slashAndOfferNext();

        _advanceTime(4 days);

        uint256 treasuryBalBefore = usdc.balanceOf(treasury);
        uint256 bidder2Collateral = (bid2Amount * COLLATERAL_BPS) / 10000;

        auction.slashAndOfferNext();

        assertEq(usdc.balanceOf(treasury), treasuryBalBefore + bidder2Collateral, "bidder2 collateral slashed");
    }

    // ── Decline after deadline reverts ──

    function test_DeclineAfterDeadline_Reverts() public {
        _advanceTime(4 days);
        auction.slashAndOfferNext();

        _advanceTime(4 days);

        vm.prank(bidder2);
        vm.expectRevert("VehicleAuction: deadline passed");
        auction.declineOffer();
    }

    function _getStatus() internal view returns (AuctionStatus) {
        (,,,,,,,,,, AuctionStatus status) = auction.config();
        return status;
    }
}
