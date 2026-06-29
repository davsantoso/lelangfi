// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SharedSetup.sol";

contract ValidatorRegistryTest is SharedSetup {
    function test_AddValidator() public {
        assertTrue(validatorRegistry.isValidator(validator));
        assertTrue(validatorRegistry.isWhitelistedValidator(validator));
    }

    function test_AddValidator_OnlyAdmin() public {
        vm.prank(validator);
        vm.expectRevert();
        validatorRegistry.addValidator(address(0x123));
    }

    function test_AddValidator_AlreadyValidator() public {
        vm.startPrank(admin);
        vm.expectRevert("ValidatorRegistry: already validator");
        validatorRegistry.addValidator(validator);
        vm.stopPrank();
    }

    function test_AddValidator_ZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert("ValidatorRegistry: zero address");
        validatorRegistry.addValidator(address(0));
        vm.stopPrank();
    }

    function test_GetValidators() public {
        address[] memory validators = validatorRegistry.getValidators();
        assertEq(validators.length, 1);
        assertEq(validators[0], validator);
    }

    function test_RemoveValidator_OnlyAdmin() public {
        vm.prank(validator);
        vm.expectRevert();
        validatorRegistry.removeValidator(validator);
    }

    function test_RemoveValidator_NotValidator() public {
        vm.startPrank(admin);
        vm.expectRevert("ValidatorRegistry: not validator");
        validatorRegistry.removeValidator(address(0x999));
        vm.stopPrank();
    }

    function test_RemoveValidator_UpdatesList() public {
        vm.prank(admin);
        validatorRegistry.removeValidator(validator);

        assertFalse(validatorRegistry.isValidator(validator));
        assertFalse(validatorRegistry.isWhitelistedValidator(validator));

        address[] memory validators = validatorRegistry.getValidators();
        assertEq(validators.length, 0);
    }
}
