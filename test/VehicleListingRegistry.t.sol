// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SharedSetup.sol";

contract VehicleListingRegistryTest is SharedSetup {
    function test_SubmitListing() public {
        vm.prank(seller);
        uint256 id = listingRegistry.submitListing("ipfs://test", 10_000 * 1e6, 1000);

        Listing memory listing = listingRegistry.getListing(id);
        assertEq(listing.seller, seller);
        assertEq(uint256(listing.status), uint256(ListingStatus.PENDING_VALIDATION));
        assertEq(listing.startPrice, 10_000 * 1e6);
    }

    function test_SubmitListing_OnlySeller() public {
        vm.prank(bidder1);
        vm.expectRevert("VehicleListingRegistry: only whitelisted seller");
        listingRegistry.submitListing("ipfs://test", 10_000 * 1e6, 1000);
    }

    function test_SubmitListing_EmptyHash() public {
        vm.prank(seller);
        vm.expectRevert("VehicleListingRegistry: empty metadata hash");
        listingRegistry.submitListing("", 10_000 * 1e6, 1000);
    }

    function test_SubmitListing_ZeroPrice() public {
        vm.prank(seller);
        vm.expectRevert("VehicleListingRegistry: zero start price");
        listingRegistry.submitListing("ipfs://test", 0, 1000);
    }

    function test_ApproveListing() public {
        vm.prank(seller);
        uint256 id = listingRegistry.submitListing("ipfs://test", 10_000 * 1e6, 1000);

        vm.prank(validator);
        listingRegistry.approveListing(id);

        Listing memory listing = listingRegistry.getListing(id);
        assertEq(uint256(listing.status), uint256(ListingStatus.APPROVED));
    }

    function test_ApproveListing_OnlyValidator() public {
        vm.prank(seller);
        uint256 id = listingRegistry.submitListing("ipfs://test", 10_000 * 1e6, 1000);

        vm.prank(seller);
        vm.expectRevert("VehicleListingRegistry: only validator");
        listingRegistry.approveListing(id);
    }

    function test_RejectListing() public {
        vm.prank(seller);
        uint256 id = listingRegistry.submitListing("ipfs://test", 10_000 * 1e6, 1000);

        vm.prank(validator);
        listingRegistry.rejectListing(id, "dokumen tidak lengkap");

        Listing memory listing = listingRegistry.getListing(id);
        assertEq(uint256(listing.status), uint256(ListingStatus.REJECTED));
        assertEq(listing.rejectionReason, "dokumen tidak lengkap");
    }

    function test_DoubleApprove_Reverts() public {
        vm.prank(seller);
        uint256 id = listingRegistry.submitListing("ipfs://test", 10_000 * 1e6, 1000);

        vm.prank(validator);
        listingRegistry.approveListing(id);

        vm.prank(validator);
        vm.expectRevert("VehicleListingRegistry: not pending");
        listingRegistry.approveListing(id);
    }

    function test_GetSellerListings() public {
        vm.prank(seller);
        listingRegistry.submitListing("ipfs://car1", 10_000 * 1e6, 1000);
        vm.prank(seller);
        listingRegistry.submitListing("ipfs://car2", 15_000 * 1e6, 1000);

        uint256[] memory listings = listingRegistry.getSellerListings(seller);
        assertEq(listings.length, 2);
    }
}
