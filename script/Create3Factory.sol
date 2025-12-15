// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @dev Tiny intermediate that does a single CREATE with msg.value.
/// Nonce is 1 for the first CREATE.
contract Create3Deployer {
    constructor() payable {}

    function deploy(bytes memory code) external payable returns (address addr) {
        assembly { addr := create(callvalue(), add(code, 0x20), mload(code)) }
    }
}

/// @notice Minimal CREATE3 factory.
/// Uses CREATE2 to deploy a one-off Deployer, then CREATE (nonce=1) to deploy initCode.
/// The final address depends ONLY on (factory addr, salt), not on initCode.
///
/// Deterministic across chains IFF the factory is at the same address everywhere.
contract Create3Factory {
    event Deployed(address addr, bytes32 indexed salt);

    /// @notice Deploy a contract via CREATE3.
    /// @param salt      User-chosen salt (same salt => same address across chains).
    /// @param initCode  Creation bytecode (can differ per chain — address stays the same).
    /// @return addr     Deployed contract address.
    function deploy(bytes32 salt, bytes memory initCode) external payable returns (address addr) {
        // 1) Deploy the ephemeral deployer deterministically (CREATE2).
        bytes memory dCode = type(Create3Deployer).creationCode;
        address intermediate = Create2.deploy(0, salt, dCode);

        // 2) Deploy the target with CREATE (nonce = 1).
        addr = Create3Deployer(intermediate).deploy{value: msg.value}(initCode);
        require(addr != address(0), "CREATE3: create failed");

        emit Deployed(addr, salt);
    }

    /// @notice Compute final CREATE3 address for `salt` without deploying.
    function compute(bytes32 salt) external view returns (address addr) {
        // Predicted intermediate (CREATE2).
        address intermediate = Create2.computeAddress(
            salt,
            keccak256(type(Create3Deployer).creationCode),
            address(this)
        );
        // RLP for CREATE nonce=1: keccak256( 0xd6, 0x94, intermediate, 0x01 )[12:]
        addr = address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xd6), bytes1(0x94), intermediate, bytes1(0x01)
        )))));
    }
}

