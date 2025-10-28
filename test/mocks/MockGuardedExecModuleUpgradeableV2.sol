// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { Execution } from "modulekit/accounts/erc7579/lib/ExecutionLib.sol";
import { TargetRegistry } from "../../src/registry/TargetRegistry.sol";

/**
 * @title MockGuardedExecModuleUpgradeableV2
 * @author Zyfi
 * @notice MOCK contract for testing upgradeability - NOT for production use
 * @dev This is a test-only mock contract used in Foundry tests to verify upgrade functionality
 */
contract MockGuardedExecModuleUpgradeableV2 is 
    ERC7579ExecutorBase,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    bytes4 private constant TRANSFER_SELECTOR = IERC20.transfer.selector;
    uint256 private constant MIN_SELECTOR_LENGTH = 4;
    uint256 private constant MIN_TRANSFER_LENGTH = 68;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    
    TargetRegistry public registry;
    uint256 public upgradeCounter; // NEW in V2 - for testing upgrade tracking
    string public upgradeMessage; // NEW in V2 - for testing upgrade initialization

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidRegistry();
    error EmptyBatch();
    error LengthMismatch();
    error TargetSelectorNotWhitelisted(address target, bytes4 selector);
    error UnauthorizedERC20Transfer(address token, address to);
    error InvalidCalldata();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _registry, address _owner) external initializer {
        if (_registry == address(0)) revert InvalidRegistry();
        
        __Ownable_init(_owner);
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        registry = TargetRegistry(_registry);
    }

    /**
     * @notice V2 specific initialization (called after upgrade)
     * @dev Used in tests to initialize new storage variables after upgrade
     */
    function initializeV2(string memory _upgradeMessage) external reinitializer(2) {
        upgradeMessage = _upgradeMessage;
        upgradeCounter = 1;
    }

    function name() external pure returns (string memory) {
        return "MockGuardedExecModuleUpgradeableV2";
    }
    
    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    function isModuleType(uint256 typeId) external pure override returns (bool) {
        return typeId == 2;
    }

    function isInitialized(address) external pure override returns (bool) {
        return true;
    }

    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        upgradeCounter++; // Track upgrades for testing
    }

    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function executeGuardedBatch(
        address[] calldata targets,
        bytes[] calldata calldatas
    ) external whenNotPaused {
        uint256 length = targets.length;
        if (length == 0) revert EmptyBatch();
        if (length != calldatas.length) revert LengthMismatch();
        
        Execution[] memory executions = new Execution[](length);
        
        for (uint256 i = 0; i < length;) {
            bytes calldata currentCalldata = calldatas[i];
            address currentTarget = targets[i];
            
            if (currentCalldata.length < MIN_SELECTOR_LENGTH) revert InvalidCalldata();
            bytes4 selector = bytes4(currentCalldata[:4]);
            
            if (!registry.isWhitelisted(currentTarget, selector)) {
                revert TargetSelectorNotWhitelisted(currentTarget, selector);
            }
            
            if (selector == TRANSFER_SELECTOR) {
                _validateERC20Transfer(currentTarget, currentCalldata);
            }
            
            executions[i] = Execution({
                target: currentTarget,
                value: 0,
                callData: currentCalldata
            });
            
            unchecked { ++i; }
        }
        
        _execute(executions);
    }

    function _validateERC20Transfer(address token, bytes calldata callData) internal view {
        if (callData.length < MIN_TRANSFER_LENGTH) revert InvalidCalldata();
        
        address to = abi.decode(callData[4:36], (address));

        if (!registry.isERC20TransferAuthorized(token, to, msg.sender)) {
            revert UnauthorizedERC20Transfer(token, to);
        }
    }

    function getRegistry() external view returns (address) {
        return address(registry);
    }

    function updateRegistry(address newRegistry) external onlyOwner {
        if (newRegistry == address(0)) revert InvalidRegistry();
        registry = TargetRegistry(newRegistry);
    }
}

