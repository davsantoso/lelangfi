// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract SellerRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    mapping(address => bool) public isSeller;
    address[] public sellerList;

    event SellerAdded(address indexed seller);
    event SellerRemoved(address indexed seller);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SellerRegistry: only admin");
        _;
    }

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function addSeller(address seller) external onlyAdmin {
        require(seller != address(0), "SellerRegistry: zero address");
        require(!isSeller[seller], "SellerRegistry: already seller");

        isSeller[seller] = true;
        sellerList.push(seller);

        emit SellerAdded(seller);
    }

    function removeSeller(address seller) external onlyAdmin {
        require(isSeller[seller], "SellerRegistry: not seller");

        isSeller[seller] = false;

        for (uint256 i = 0; i < sellerList.length; i++) {
            if (sellerList[i] == seller) {
                sellerList[i] = sellerList[sellerList.length - 1];
                sellerList.pop();
                break;
            }
        }

        emit SellerRemoved(seller);
    }

    function getSellers() external view returns (address[] memory) {
        return sellerList;
    }

    function isWhitelistedSeller(address seller) external view returns (bool) {
        return isSeller[seller];
    }
}
