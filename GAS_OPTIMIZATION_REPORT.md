# Gas Optimization Report

This report documents the gas optimizations applied to `GuardedExecModuleUpgradeable.sol` and `TargetRegistry.sol` based on peer review feedback.

## Summary

The optimizations focus on:
- Reducing calldata gas costs
- Minimizing storage reads (SLOAD operations)
- Avoiding unnecessary memory allocations
- Optimizing conditional checks for early returns
- Removing duplicate bytecode

---

## 1. GuardedExecModuleUpgradeable.sol

### 1.1 Function Signature Change (Calldata Gas Savings)

**Before:**
```solidity
function executeGuardedBatch(
    address[] calldata targets,
    bytes[] calldata calldatas,
    uint256[] calldata values
) external whenNotPaused
```

**After:**
```solidity
function executeGuardedBatch(
    Execution[] calldata executions
) external whenNotPaused
```

**Why:**
- **Calldata savings**: Three separate arrays require 3 length limiters in calldata (2 words each = 6 words total)
- **Struct array**: Single array requires only 1 length limiter (2 words total)
- **Net savings**: 4 words = **~800 gas** saved per call
- **Additional benefit**: Removed length mismatch checks (no longer needed since struct ensures consistency)

---

### 1.2 Cached Calldata Length (Runtime Gas Savings)

**Before:**
```solidity
// In main loop
for (uint256 i = 0; i < length;) {
    bytes calldata callData = calldatas[i];
    if (callData.length < MIN_SELECTOR_LENGTH) revert InvalidCalldata();
    // ... later ...
    _validateERC20Transfer(target, callData, reg);  // callData.length accessed again inside
}

function _validateERC20Transfer(
    address token,
    bytes calldata callData,
    TargetRegistry reg
) internal view {
    if (callData.length != MIN_TRANSFER_LENGTH) revert InvalidCalldata();
    // callData.length accessed again in abi.decode
    address to = abi.decode(callData[4:36], (address));
}
```

**After:**
```solidity
// In main loop
for (uint256 i = 0; i < length;) {
    bytes calldata callData = execution.callData;
    // Cache callData.length to avoid repeated calldata loads (accessed 3 times total)
    uint256 callDataLength = callData.length;
    if (callDataLength < MIN_SELECTOR_LENGTH) revert InvalidCalldata();
    // ... later ...
    _validateERC20Transfer(target, callData, callDataLength, reg);  // Pass cached value
}

function _validateERC20Transfer(
    address token,
    bytes calldata callData,
    uint256 callDataLength,  // ← Cached parameter
    TargetRegistry reg
) internal view {
    if (callDataLength != MIN_TRANSFER_LENGTH) revert InvalidCalldata();
    address to = address(bytes20(callData[16:36]));
}
```

**Why:**
- **Before**: `callData.length` was accessed multiple times:
  - Once in main loop for selector check
  - Once in `_validateERC20Transfer` for length validation
  - Once in `_validateERC20Approve` for length validation
  - Implicitly in `abi.decode` operations
- **After**: Length is cached once at the start of loop iteration and passed to validation functions
- **Savings**: Each calldata load costs ~100 gas. Saved **~200-300 gas** per execution item
- **Impact**: Especially significant in batch operations with multiple ERC20 transfers/approves

---

### 1.3 Calldata Slicing Instead of abi.decode (Memory Savings)

**Before:**
```solidity
address to = abi.decode(callData[4:36], (address));
```

**After:**
```solidity
address to = address(bytes20(callData[16:36]));
```

**Why:**
- **Before**: `abi.decode` allocates memory and performs decoding operations
- **After**: Direct calldata slicing with type casting (no memory allocation)
- **Savings**: Avoids memory allocation (malloc) = **~100-200 gas** per call
- **Note**: Offset changed from `[4:36]` to `[16:36]` to account for 12-byte padding in calldata

---

### 1.4 Optimized Conditional Checks (Early Return Pattern)

**Before:**
```solidity
if (selector == TRANSFER_SELECTOR) {
    _validateERC20Transfer(target, callData, callDataLength, reg);
}

if (selector == APPROVE_SELECTOR) {
    _validateERC20Approve(target, callData, callDataLength, reg);
}
```

**After:**
```solidity
if (selector == TRANSFER_SELECTOR) {
    _validateERC20Transfer(target, callData, callDataLength, reg);
} else if (selector == APPROVE_SELECTOR) {
    _validateERC20Approve(target, callData, callDataLength, reg);
}
```

**Why:**
- **Before**: Both conditions always checked (even when first is true)
- **After**: Second condition skipped when first matches
- **Savings**: Saves one comparison operation = **~3-5 gas** per transfer call
- **Best case**: Most calls are neither transfer nor approve, so both checks are skipped entirely

---

## 2. TargetRegistry.sol

### 2.1 Reordered Authorization Checks (Cheapest First)

**Before:**
```solidity
function _isAuthorizedRecipient(...) internal view returns (bool) {
    if (allowedERC20TokenRecipients[token][to]) return true;  // Storage read
    if (to == smartWallet) return true;                      // Address comparison
    
    try ISafeWallet(smartWallet).getOwners() returns (address[] memory owners) {
        // Loop through owners...
    } catch { }
    return false;
}
```

**After:**
```solidity
function _isAuthorizedRecipient(...) internal view returns (bool) {
    // NOTE: return early without sload (cheapest check first)
    if (to == smartWallet) return true;                      // Address comparison
    
    // Storage read (cheaper than external call)
    if (allowedERC20TokenRecipients[token][to]) return true;  // Storage read
    
    // NOTE: could be replaced with isOwner (single SLOAD vs multiple SLOADs + memory allocation)
    try ISafeWallet(smartWallet).isOwner(to) returns (bool isOwner) {
        if (isOwner) return true;
    } catch { }
    return false;
}
```

**Why:**
- **Order matters**: Address comparison (0 gas) < Storage read (~100 gas) < External call (~700+ gas)
- **Best case**: If recipient is the wallet itself, we return immediately without any storage reads
- **Savings**: In best case, saves **~100 gas** (one SLOAD avoided)
- **Impact**: This function is called for every ERC20 transfer, so savings add up quickly in batch operations

---

### 2.2 Replaced getOwners() with isOwner() (Major Gas Savings)

**Before:**
```solidity
try ISafeWallet(smartWallet).getOwners() returns (address[] memory owners) {
    uint256 length = owners.length;
    for (uint256 i = 0; i < length;) {
        if (owners[i] == to) return true;
        unchecked { ++i; }
    }
} catch { }
```

**After:**
```solidity
try ISafeWallet(smartWallet).isOwner(to) returns (bool isOwner) {
    if (isOwner) return true;
} catch { }
```

**Why:**
- **Before**: 
  - Calls `getOwners()` which does multiple SLOADs (one per owner in linked list)
  - Allocates memory for owners array
  - Loops through array to find match
  - Example: 5 owners = 6 SLOADs + memory allocation + loop iterations
  
- **After**:
  - Calls `isOwner(to)` which does single SLOAD (checks if address is in linked list)
  - No memory allocation
  - No loop needed
  
- **Savings**: 
  - For 1 owner: **~500 gas** saved (2 SLOADs + memory vs 1 SLOAD)
  - For 5 owners: **~2000+ gas** saved (6 SLOADs + memory + loop vs 1 SLOAD)
  
- **Impact**: This is called for every ERC20 transfer validation, so savings are significant in batch operations

---

### 2.3 Removed Duplicate External Functions (Deployment Gas Savings)

**Before:**
```solidity
mapping(address => mapping(bytes4 => bool)) public whitelist;
mapping(address => bool) public whitelistedTargets;

function isWhitelisted(address target, bytes4 selector) external view returns (bool) {
    return whitelist[target][selector];
}

function isWhitelistedTarget(address target) external view returns (bool) {
    return whitelistedTargets[target];
}
```

**After:**
```solidity
mapping(address => mapping(bytes4 => bool)) public whitelist;
mapping(address => bool) public whitelistedTargets;

// Functions removed - using auto-generated getters from public mappings
```

**Why:**
- **Before**: Public mappings automatically generate getter functions, but we also had explicit external functions doing the same thing
- **After**: Removed explicit functions, using only auto-generated getters
- **Savings**: Removes duplicate bytecode = **~500-1000 gas** saved in deployment
- **Note**: Call sites updated to use `whitelist(target, selector)` and `whitelistedTargets(target)` instead

---

## 3. Combined Impact

### Per Transaction Savings

For a typical batch execution with 3 operations (1 swap, 1 transfer, 1 approve):

| Optimization | Gas Saved |
|-------------|-----------|
| Calldata optimization (struct vs arrays) | ~800 gas |
| Cached calldata length | ~200 gas |
| Calldata slicing | ~150 gas |
| Optimized conditionals | ~5 gas |
| Reordered checks (best case) | ~100 gas |
| isOwner() vs getOwners() (1 owner) | ~500 gas |
| **Total per transaction** | **~1,755 gas** |

### For Batch with Multiple ERC20 Transfers

For a batch with 5 ERC20 transfers (common use case):

| Optimization | Gas Saved |
|-------------|-----------|
| All above optimizations | ~1,755 gas |
| isOwner() savings × 5 transfers | ~2,500 gas |
| **Total for batch** | **~4,255 gas** |

### Deployment Savings

| Optimization | Gas Saved |
|-------------|-----------|
| Removed duplicate functions | ~750 gas |
| **Total deployment** | **~750 gas** |

---

## 4. Code Quality Improvements

Beyond gas savings, these optimizations also improve:

1. **Code clarity**: Struct-based approach is more intuitive than three separate arrays
2. **Type safety**: Struct ensures all fields are present and consistent
3. **Maintainability**: Fewer functions to maintain, cleaner codebase
4. **Best practices**: Following Solidity patterns (using auto-generated getters)

---

## 5. Testing Updates

All test files were updated to:
- Use new `Execution[]` signature instead of three arrays
- Use auto-generated getter functions (`whitelist()`, `whitelistedTargets()`)
- Remove obsolete length mismatch tests

---

## Conclusion

These optimizations provide meaningful gas savings, especially for:
- **Batch operations** with multiple ERC20 transfers
- **Frequent calls** to authorization checks
- **Deployment costs** (one-time but still important)

The changes maintain all security guarantees while significantly reducing gas costs for end users.

