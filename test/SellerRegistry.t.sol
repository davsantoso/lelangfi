// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SharedSetup.sol";

contract SellerRegistryTest is SharedSetup {
    function test_AddSeller() public {
        assertTrue(sellerRegistry.isSeller(seller));
        assertTrue(sellerRegistry.isWhitelistedSeller(seller));
    }

    function test_AddSeller_OnlyAdmin() public {
        vm.prank(seller);
        vm.expectRevert();
        sellerRegistry.addSeller(address(0x123));
    }

    function test_AddSeller_AlreadySeller() public {
        vm.startPrank(admin);
        vm.expectRevert("SellerRegistry: already seller");
        sellerRegistry.addSeller(seller);
        vm.stopPrank();
    }

    function test_AddSeller_ZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert("SellerRegistry: zero address");
        sellerRegistry.addSeller(address(0));
        vm.stopPrank();
    }

    function test_RemoveSeller() public {
        vm.prank(admin);
        sellerRegistry.removeSeller(seller);

        assertFalse(sellerRegistry.isSeller(seller));
        assertFalse(sellerRegistry.isWhitelistedSeller(seller));
    }

    function test_RemoveSeller_OnlyAdmin() public {
        vm.prank(seller);
        vm.expectRevert();
        sellerRegistry.removeSeller(seller);
    }

    function test_RemoveSeller_NotSeller() public {
        vm.startPrank(admin);
        vm.expectRevert("SellerRegistry: not seller");
        sellerRegistry.removeSeller(address(0x999));
        vm.stopPrank();
    }

    function test_GetSellers() public {
        address[] memory sellers = sellerRegistry.getSellers();
        assertEq(sellers.length, 2);
        assertEq(sellers[0], seller);
        assertEq(sellers[1], sellerTwo);
    }

    function test_RemoveSeller_UpdatesList() public {
        vm.prank(admin);
        sellerRegistry.removeSeller(seller);

        address[] memory sellers = sellerRegistry.getSellers();
        assertEq(sellers.length, 1);
        assertEq(sellers[0], sellerTwo);
    }
}
