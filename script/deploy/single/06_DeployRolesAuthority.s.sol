// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { ManagerWithMerkleVerification } from "./../../../src/base/Roles/ManagerWithMerkleVerification.sol";
import { BoringVault } from "./../../../src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "./../../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "./../../../src/base/Roles/AccountantWithRateProviders.sol";
import { BaseScript } from "../../Base.s.sol";
import { ConfigReader } from "../../ConfigReader.s.sol";
import { CrossChainTellerBase } from "../../../src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";

uint8 constant STRATEGIST_ROLE = 1;
uint8 constant MANAGER_ROLE = 2;
uint8 constant TELLER_ROLE = 3;
uint8 constant UPDATE_EXCHANGE_RATE_ROLE = 4;
uint8 constant SOLVER_ROLE = 5;

/**
 * NOTE Deploys with `Authority` set to zero bytes.
 */
contract DeployRolesAuthority is BaseScript {
    using StdJson for string;

    function run() public virtual returns (address rolesAuthority) {
        return deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public virtual override broadcast returns (address) {
        // Require config Values
        require(config.boringVault.code.length != 0, "boringVault must have code");
        require(config.manager.code.length != 0, "manager must have code");
        require(config.teller.code.length != 0, "teller must have code");
        require(config.accountant.code.length != 0, "accountant must have code");
        require(config.boringVault != address(0), "boringVault");
        require(config.manager != address(0), "manager");
        require(config.teller != address(0), "teller");
        require(config.accountant != address(0), "accountant");
        require(config.strategist != address(0), "strategist");

        // Create Contract
        bytes memory creationCode = type(RolesAuthority).creationCode;
        RolesAuthority rolesAuthority = RolesAuthority(
            CREATEX.deployCreate3(
                config.rolesAuthoritySalt,
                abi.encodePacked(
                    creationCode,
                    abi.encode(
                        broadcaster,
                        address(0) // `Authority`
                    )
                )
            )
        );

        // Setup initial roles configurations
        // --- Users ---
        // 1. VAULT_STRATEGIST (BOT EOA)
        // 2. MANAGER (CONTRACT)
        // 3. TELLER (CONTRACT)
        // --- Roles ---
        // 1. STRATEGIST_ROLE
        //     - manager.manageVaultWithMerkleVerification
        //     - assigned to VAULT_STRATEGIST
        // 2. MANAGER_ROLE
        //     - boringVault.manage()
        //     - assigned to MANAGER
        // 3. TELLER_ROLE
        //     - boringVault.enter()
        //     - boringVault.exit()
        //     - assigned to TELLER
        // --- Public ---
        // 1. teller.deposit
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            config.manager,
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, config.boringVault, bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))), true
        );

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            config.boringVault,
            bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))),
            true
        );

        rolesAuthority.setRoleCapability(TELLER_ROLE, config.boringVault, BoringVault.enter.selector, true);

        rolesAuthority.setRoleCapability(TELLER_ROLE, config.boringVault, BoringVault.exit.selector, true);

        rolesAuthority.setPublicCapability(config.teller, TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(config.teller, CrossChainTellerBase.bridge.selector, true);
        rolesAuthority.setPublicCapability(config.teller, CrossChainTellerBase.depositAndBridge.selector, true);

        rolesAuthority.setRoleCapability(
            UPDATE_EXCHANGE_RATE_ROLE, config.accountant, AccountantWithRateProviders.updateExchangeRate.selector, true
        );

        // --- Assign roles to users ---

        rolesAuthority.setUserRole(config.strategist, STRATEGIST_ROLE, true);

        rolesAuthority.setUserRole(config.manager, MANAGER_ROLE, true);

        rolesAuthority.setUserRole(config.teller, TELLER_ROLE, true);

        rolesAuthority.setUserRole(config.exchangeRateBot, UPDATE_EXCHANGE_RATE_ROLE, true);

        // Post Deploy Checks
        require(
            rolesAuthority.doesUserHaveRole(config.strategist, STRATEGIST_ROLE),
            "strategist should have STRATEGIST_ROLE"
        );
        require(rolesAuthority.doesUserHaveRole(config.manager, MANAGER_ROLE), "manager should have MANAGER_ROLE");
        require(rolesAuthority.doesUserHaveRole(config.teller, TELLER_ROLE), "teller should have TELLER_ROLE");
        require(
            rolesAuthority.doesUserHaveRole(config.exchangeRateBot, UPDATE_EXCHANGE_RATE_ROLE),
            "exchangeRateBot should have UPDATE_EXCHANGE_RATE_ROLE"
        );
        require(
            rolesAuthority.canCall(
                config.strategist,
                config.manager,
                ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector
            ),
            "strategist should be able to call manageVaultWithMerkleVerification"
        );
        require(
            rolesAuthority.canCall(
                config.manager, config.boringVault, bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)")))
            ),
            "manager should be able to call boringVault.manage"
        );
        require(
            rolesAuthority.canCall(
                config.manager,
                config.boringVault,
                bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])")))
            ),
            "manager should be able to call boringVault.manage"
        );
        require(
            rolesAuthority.canCall(config.teller, config.boringVault, BoringVault.enter.selector),
            "teller should be able to call boringVault.enter"
        );
        require(
            rolesAuthority.canCall(config.teller, config.boringVault, BoringVault.exit.selector),
            "teller should be able to call boringVault.exit"
        );
        require(
            rolesAuthority.canCall(
                config.exchangeRateBot, config.accountant, AccountantWithRateProviders.updateExchangeRate.selector
            ),
            "exchangeRateBot should be able to call accountant.updateExchangeRate"
        );
        require(
            rolesAuthority.canCall(address(1), config.teller, TellerWithMultiAssetSupport.deposit.selector),
            "anyone should be able to call teller.deposit"
        );

        return address(rolesAuthority);
    }
}
