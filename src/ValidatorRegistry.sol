// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract ValidatorRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    mapping(address => bool) public isValidator;
    address[] public validatorList;

    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "ValidatorRegistry: only admin");
        _;
    }

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function addValidator(address validator) external onlyAdmin {
        require(validator != address(0), "ValidatorRegistry: zero address");
        require(!isValidator[validator], "ValidatorRegistry: already validator");

        isValidator[validator] = true;
        validatorList.push(validator);

        emit ValidatorAdded(validator);
    }

    function removeValidator(address validator) external onlyAdmin {
        require(isValidator[validator], "ValidatorRegistry: not validator");

        isValidator[validator] = false;

        for (uint256 i = 0; i < validatorList.length; i++) {
            if (validatorList[i] == validator) {
                validatorList[i] = validatorList[validatorList.length - 1];
                validatorList.pop();
                break;
            }
        }

        emit ValidatorRemoved(validator);
    }

    function getValidators() external view returns (address[] memory) {
        return validatorList;
    }

    function isWhitelistedValidator(address validator) external view returns (bool) {
        return isValidator[validator];
    }
}
