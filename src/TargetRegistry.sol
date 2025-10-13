// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ITargetRegistry {
    function isWhitelisted(address target) external view returns (bool);
}

contract TargetRegistry is ITargetRegistry {
    event TargetAdded(address indexed target);
    event TargetRemoved(address indexed target);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    address public owner;
    mapping(address => bool) private _wl;

    modifier onlyOwner() { require(msg.sender == owner, "not-owner"); _; }

    constructor(address _owner) {
        require(_owner != address(0), "zero-owner");
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function setOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "zero-owner");
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    function add(address target) external onlyOwner { _wl[target] = true;  emit TargetAdded(target); }
    function remove(address target) external onlyOwner { _wl[target] = false; emit TargetRemoved(target); }

    function isWhitelisted(address target) external view returns (bool) { return _wl[target]; }
}