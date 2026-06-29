// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SellerRegistry.sol";
import "../src/ValidatorRegistry.sol";
import "../src/VehicleListingRegistry.sol";
import "../src/VehicleOwnershipNFT.sol";
import "../src/VehicleAuctionFactory.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address usdcToken = vm.envAddress("USDC_TOKEN");
        address treasury = vm.envOr("TREASURY", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy registries
        SellerRegistry sellerRegistry = new SellerRegistry(deployer);
        ValidatorRegistry validatorRegistry = new ValidatorRegistry(deployer);
        VehicleListingRegistry listingRegistry = new VehicleListingRegistry(
            deployer,
            address(sellerRegistry),
            address(validatorRegistry)
        );

        // Deploy NFT contract — factory is the initial minter
        VehicleOwnershipNFT ownershipNFT = new VehicleOwnershipNFT(deployer, deployer);

        // Deploy factory
        VehicleAuctionFactory factory = new VehicleAuctionFactory(
            deployer,
            usdcToken,
            treasury,
            address(sellerRegistry),
            address(validatorRegistry),
            address(listingRegistry),
            address(ownershipNFT)
        );

        // Grant DEFAULT_ADMIN_ROLE on NFT to factory so it can grant MINTER_ROLE to each auction
        ownershipNFT.grantRole(ownershipNFT.DEFAULT_ADMIN_ROLE(), address(factory));

        // Grant MINTER_ROLE on NFT to the factory so it can grant to individual auctions
        ownershipNFT.grantRole(ownershipNFT.MINTER_ROLE(), address(factory));

        // Authorize factory to call markListingAuctionCreated on behalf of the seller
        listingRegistry.authorizeFactory(address(factory));

        vm.stopBroadcast();

        // Log deployed addresses
        vm.serializeAddress("deploy", "sellerRegistry", address(sellerRegistry));
        vm.serializeAddress("deploy", "validatorRegistry", address(validatorRegistry));
        vm.serializeAddress("deploy", "listingRegistry", address(listingRegistry));
        vm.serializeAddress("deploy", "ownershipNFT", address(ownershipNFT));
        vm.serializeAddress("deploy", "factory", address(factory));
        string memory output = vm.serializeAddress("deploy", "usdcToken", usdcToken);

        vm.writeJson(output, "deployments.json");
    }
}
