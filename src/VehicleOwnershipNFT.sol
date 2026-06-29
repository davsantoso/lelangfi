// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract VehicleOwnershipNFT is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private _tokenIdCounter;

    struct VehicleInfo {
        uint256 listingId;
        string vehicleMetadataHash;
        address auctionAddress;
        address buyerAddress;
        uint256 paidAmount;
        uint256 timestamp;
    }

    mapping(uint256 => VehicleInfo) public vehicleInfo;
    mapping(address => uint256[]) public buyerTokenIds;
    mapping(uint256 => bool) public isTransferable;

    event VehicleNFTCreated(uint256 indexed tokenId, uint256 indexed listingId, address indexed buyer);
    event VehicleNFTBurn(uint256 indexed tokenId);

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "VehicleOwnershipNFT: only minter");
        _;
    }

    constructor(address admin, address minter) ERC721("VehicleOwnership", "VOWN") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
    }

    function mint(
        address to,
        uint256 listingId,
        string calldata vehicleMetadataHash,
        address auctionAddress,
        uint256 paidAmount
    ) external onlyMinter returns (uint256) {
        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;

        _safeMint(to, tokenId);

        vehicleInfo[tokenId] = VehicleInfo({
            listingId: listingId,
            vehicleMetadataHash: vehicleMetadataHash,
            auctionAddress: auctionAddress,
            buyerAddress: to,
            paidAmount: paidAmount,
            timestamp: block.timestamp
        });

        buyerTokenIds[to].push(tokenId);

        emit VehicleNFTCreated(tokenId, listingId, to);

        return tokenId;
    }

    function setTransferable(uint256 tokenId, bool transferable) external onlyMinter {
        isTransferable[tokenId] = transferable;
    }

    function burn(uint256 tokenId) external onlyMinter {
        address owner = _ownerOf(tokenId);
        require(owner != address(0), "VehicleOwnershipNFT: token not found");

        // Remove tokenId from owner's array
        uint256[] storage tokens = buyerTokenIds[owner];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }

        delete vehicleInfo[tokenId];

        _burn(tokenId);

        emit VehicleNFTBurn(tokenId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        if (from != address(0) && to != address(0)) {
            require(isTransferable[tokenId], "VehicleOwnershipNFT: not transferable yet");
        }

        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
