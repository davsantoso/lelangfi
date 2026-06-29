// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./SellerRegistry.sol";
import "./ValidatorRegistry.sol";

enum ListingStatus {
    PENDING_VALIDATION,
    APPROVED,
    REJECTED,
    AUCTION_CREATED
}

struct Listing {
    uint256 id;
    address seller;
    string vehicleMetadataHash;
    uint256 startPrice;
    uint256 collateralBps;
    ListingStatus status;
    string rejectionReason;
}

contract VehicleListingRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    SellerRegistry public sellerRegistry;
    ValidatorRegistry public validatorRegistry;

    uint256 public listingCounter;
    mapping(uint256 => Listing) public listings;
    mapping(address => uint256[]) public sellerListings;
    mapping(address => bool) public authorizedFactories;

    event ListingSubmitted(uint256 indexed listingId, address indexed seller, string vehicleMetadataHash, uint256 startPrice);
    event ListingApproved(uint256 indexed listingId, address indexed validator);
    event ListingRejected(uint256 indexed listingId, address indexed validator, string reason);
    event FactoryAuthorized(address indexed factory);
    event FactoryUnauthorized(address indexed factory);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "VehicleListingRegistry: only admin");
        _;
    }

    modifier onlySeller() {
        require(sellerRegistry.isWhitelistedSeller(msg.sender), "VehicleListingRegistry: only whitelisted seller");
        _;
    }

    modifier onlyValidator() {
        require(validatorRegistry.isWhitelistedValidator(msg.sender), "VehicleListingRegistry: only validator");
        _;
    }

    constructor(address admin, address _sellerRegistry, address _validatorRegistry) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        sellerRegistry = SellerRegistry(_sellerRegistry);
        validatorRegistry = ValidatorRegistry(_validatorRegistry);
    }

    function submitListing(string calldata vehicleMetadataHash, uint256 startPrice, uint256 collateralBps) external onlySeller returns (uint256) {
        require(bytes(vehicleMetadataHash).length > 0, "VehicleListingRegistry: empty metadata hash");
        require(startPrice > 0, "VehicleListingRegistry: zero start price");
        require(collateralBps > 0 && collateralBps <= 2000, "VehicleListingRegistry: invalid collateral bps");

        listingCounter++;
        uint256 listingId = listingCounter;

        listings[listingId] = Listing({
            id: listingId,
            seller: msg.sender,
            vehicleMetadataHash: vehicleMetadataHash,
            startPrice: startPrice,
            collateralBps: collateralBps,
            status: ListingStatus.PENDING_VALIDATION,
            rejectionReason: ""
        });

        sellerListings[msg.sender].push(listingId);

        emit ListingSubmitted(listingId, msg.sender, vehicleMetadataHash, startPrice);

        return listingId;
    }

    function approveListing(uint256 listingId) external onlyValidator {
        Listing storage listing = listings[listingId];
        require(listing.id == listingId, "VehicleListingRegistry: listing not found");
        require(listing.status == ListingStatus.PENDING_VALIDATION, "VehicleListingRegistry: not pending");

        listing.status = ListingStatus.APPROVED;

        emit ListingApproved(listingId, msg.sender);
    }

    function rejectListing(uint256 listingId, string calldata reason) external onlyValidator {
        Listing storage listing = listings[listingId];
        require(listing.id == listingId, "VehicleListingRegistry: listing not found");
        require(listing.status == ListingStatus.PENDING_VALIDATION, "VehicleListingRegistry: not pending");

        listing.status = ListingStatus.REJECTED;
        listing.rejectionReason = reason;

        emit ListingRejected(listingId, msg.sender, reason);
    }

    function authorizeFactory(address factory) external onlyAdmin {
        authorizedFactories[factory] = true;
        emit FactoryAuthorized(factory);
    }

    function unauthorizeFactory(address factory) external onlyAdmin {
        authorizedFactories[factory] = false;
        emit FactoryUnauthorized(factory);
    }

    function markListingAuctionCreated(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(
            listing.seller == msg.sender || authorizedFactories[msg.sender],
            "VehicleListingRegistry: not authorized"
        );
        require(listing.status == ListingStatus.APPROVED, "VehicleListingRegistry: not approved");

        listing.status = ListingStatus.AUCTION_CREATED;
    }

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getSellerListings(address seller) external view returns (uint256[] memory) {
        return sellerListings[seller];
    }
}
