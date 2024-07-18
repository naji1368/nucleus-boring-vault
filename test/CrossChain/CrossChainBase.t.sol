// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {CrossChainTellerBase} from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";

abstract contract CrossChainBaseTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;

    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant MINTER_ROLE = 7;
    uint8 public constant BURNER_ROLE = 8;
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;
    uint8 public constant CAN_SOLVE_ROLE = 11;

    AccountantWithRateProviders public accountant;
    address public payout_address = vm.addr(7777777);
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20 internal constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    RolesAuthority public rolesAuthority;

    uint32 public constant SOURCE_SELECTOR = 1;
    uint32 public constant DESTINATION_SELECTOR = 2;

    CrossChainTellerBase sourceTeller;
    CrossChainTellerBase destinationTeller;

    function _deploySourceAndDestinationTeller() internal virtual{
    }

    function setUp() public virtual{
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19363419;
        _startFork(rpcKey, blockNumber);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);

        accountant = new AccountantWithRateProviders(
            address(this), address(boringVault), payout_address, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
        );

        _deploySourceAndDestinationTeller();

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

        boringVault.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        sourceTeller.setAuthority(rolesAuthority);
        destinationTeller.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(boringVault), BoringVault.exit.selector, true);

        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.addAsset.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.removeAsset.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.bulkDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.refundDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setPublicCapability(address(sourceTeller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(
            address(sourceTeller), TellerWithMultiAssetSupport.depositWithPermit.selector, true
        );
        rolesAuthority.setPublicCapability(address(destinationTeller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(
            address(destinationTeller), TellerWithMultiAssetSupport.depositWithPermit.selector, true
        );
        
        rolesAuthority.setPublicCapability(address(sourceTeller), CrossChainTellerBase.bridge.selector, true);
        rolesAuthority.setPublicCapability(address(destinationTeller), CrossChainTellerBase.bridge.selector, true);
        rolesAuthority.setPublicCapability(address(sourceTeller), CrossChainTellerBase.depositAndBridge.selector, true);
        rolesAuthority.setPublicCapability(address(destinationTeller), CrossChainTellerBase.depositAndBridge.selector, true);

        rolesAuthority.setUserRole(address(sourceTeller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(sourceTeller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(destinationTeller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(destinationTeller), BURNER_ROLE, true);

        sourceTeller.addAsset(WETH);
        sourceTeller.addAsset(ERC20(NATIVE));
        sourceTeller.addAsset(EETH);
        sourceTeller.addAsset(WEETH);

        destinationTeller.addAsset(WETH);
        destinationTeller.addAsset(ERC20(NATIVE));
        destinationTeller.addAsset(EETH);
        destinationTeller.addAsset(WEETH);

        accountant.setRateProviderData(EETH, true, address(0));
        accountant.setRateProviderData(WEETH, false, address(WEETH_RATE_PROVIDER));

        // Give BoringVault some WETH, and this address some shares, and LINK.
        deal(address(WETH), address(boringVault), 1_000e18);
        deal(address(boringVault), address(this), 1_000e18, true);
        deal(address(LINK), address(this), 1_000e18);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}
