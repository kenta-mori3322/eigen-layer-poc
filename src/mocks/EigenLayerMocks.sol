// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../external/interfaces/IAllocationManager.sol";
import "forge-std/Test.sol";

/// @title Mock AllocationManager for PoC Testing
/// @notice This mock simulates the AllocationManager behavior in a controlled environment
/// @dev DO NOT use this against production contracts
contract MockAllocationManager is IAllocationManager, Test {

    uint32 public constant DEALLOCATION_DELAY = 1209600; // 14 days in blocks (assuming 12s blocks)
    
    mapping(bytes32 => bool) public operatorSets;
    mapping(bytes32 => address) public slashers;
    mapping(address => mapping(bytes32 => RegistrationStatus)) public registrationStatus;
    mapping(address => mapping(bytes32 => mapping(IStrategy => Allocation))) public allocations;
    mapping(address => mapping(IStrategy => uint64)) public maxMagnitudes;
    mapping(address => mapping(bytes32 => bool)) public operatorSetMembership;
    
    uint256 public slashIdCounter;

    struct RegistrationStatus {
        bool registered;
        uint32 slashableUntil;
    }

    constructor() {}

    function slashOperator(
        address avs,
        SlashingParams calldata params
    ) external returns (uint256 slashId, uint256[] memory shares) {
        OperatorSet memory operatorSet = OperatorSet(avs, params.operatorSetId);
        bytes32 operatorSetKey = keccak256(abi.encodePacked(avs, params.operatorSetId));
        
        // VULNERABILITY #1: No validation that operator actually misbehaved
        require(msg.sender == slashers[operatorSetKey], "Invalid slasher");
        require(isOperatorSlashable(params.operator, operatorSet), "Operator not slashable");
        
        slashId = ++slashIdCounter;
        shares = new uint256[](params.strategies.length);
        
        for (uint256 i = 0; i < params.strategies.length; i++) {
            Allocation storage allocation = allocations[params.operator][operatorSetKey][params.strategies[i]];
            
            if (allocation.currentMagnitude == 0) {
                shares[i] = 0;
                continue;
            }
            
            // VULNERABILITY #4: Rounding up can cause over-slashing
            uint64 slashedMagnitude = uint64((uint256(allocation.currentMagnitude) * params.wadsToSlash[i] + 1e18 - 1) / 1e18); // Round up
            
            allocation.currentMagnitude -= slashedMagnitude;
            maxMagnitudes[params.operator][params.strategies[i]] -= slashedMagnitude;
            
            // Calculate shares slashed (simplified)
            shares[i] = uint256(slashedMagnitude);
        }
    }

    function modifyAllocations(
        address operator,
        AllocateParams[] calldata params
    ) external {
        for (uint256 i = 0; i < params.length; i++) {
            bytes32 operatorSetKey = keccak256(abi.encodePacked(params[i].operatorSet.avs, params[i].operatorSet.id));
            
            for (uint256 j = 0; j < params[i].strategies.length; j++) {
                Allocation storage allocation = allocations[operator][operatorSetKey][params[i].strategies[j]];
                
                int128 pendingDiff = int128(uint128(params[i].newMagnitudes[j])) - int128(uint128(allocation.currentMagnitude));
                require(pendingDiff != 0, "Same magnitude");
                
                if (pendingDiff < 0) {
                    // Deallocation - if slashable, delay applies
                    if (isOperatorSlashable(operator, params[i].operatorSet)) {
                        allocation.effectBlock = uint32(block.number) + DEALLOCATION_DELAY + 1;
                    } else {
                        allocation.currentMagnitude = params[i].newMagnitudes[j];
                        allocation.effectBlock = uint32(block.number);
                    }
                } else {
                    // Allocation
                    require(uint64(uint128(allocation.currentMagnitude + uint128(pendingDiff))) <= maxMagnitudes[operator][params[i].strategies[j]], "Insufficient magnitude");
                    allocation.currentMagnitude = params[i].newMagnitudes[j];
                    allocation.effectBlock = uint32(block.number);
                }
            }
        }
    }

    function deregisterFromOperatorSets(
        DeregisterParams calldata params
    ) external {
        for (uint256 i = 0; i < params.operatorSetIds.length; i++) {
            bytes32 operatorSetKey = keccak256(abi.encodePacked(params.avs, params.operatorSetIds[i]));
            
            operatorSetMembership[params.operator][operatorSetKey] = false;
            
            // VULNERABILITY #2: Operator remains slashable after deregistration
            registrationStatus[params.operator][operatorSetKey] = RegistrationStatus({
                registered: false,
                slashableUntil: uint32(block.number) + DEALLOCATION_DELAY
            });
        }
    }

    function createOperatorSets(
        address avs,
        CreateSetParamsV2[] calldata params
    ) external {
        for (uint256 i = 0; i < params.length; i++) {
            bytes32 operatorSetKey = keccak256(abi.encodePacked(avs, params[i].operatorSetId));
            operatorSets[operatorSetKey] = true;
            slashers[operatorSetKey] = params[i].slasher;
        }
    }

    function updateAVSMetadataURI(
        address avs,
        string calldata metadataURI
    ) external {
        // Mock implementation - just emit event if needed
    }

    function getAllocation(
        address operator,
        OperatorSet memory operatorSet,
        IStrategy strategy
    ) external view returns (Allocation memory) {
        bytes32 operatorSetKey = keccak256(abi.encodePacked(operatorSet.avs, operatorSet.id));
        return allocations[operator][operatorSetKey][strategy];
    }

    function getMaxMagnitudes(
        address operator,
        IStrategy[] memory strategies
    ) external view returns (uint256[] memory) {
        uint256[] memory magnitudes = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            magnitudes[i] = maxMagnitudes[operator][strategies[i]];
        }
        return magnitudes;
    }

    function isOperatorSlashable(
        address operator,
        OperatorSet memory operatorSet
    ) public view returns (bool) {
        bytes32 operatorSetKey = keccak256(abi.encodePacked(operatorSet.avs, operatorSet.id));
        RegistrationStatus memory status = registrationStatus[operator][operatorSetKey];
        return status.registered || block.number <= status.slashableUntil;
    }

    function isMemberOfOperatorSet(
        address operator,
        OperatorSet memory operatorSet
    ) external view returns (bool) {
        bytes32 operatorSetKey = keccak256(abi.encodePacked(operatorSet.avs, operatorSet.id));
        return operatorSetMembership[operator][operatorSetKey];
    }

    // Helper functions for test setup
    function setOperatorRegistered(address operator, OperatorSet memory operatorSet, bool registered) external {
        bytes32 operatorSetKey = keccak256(abi.encodePacked(operatorSet.avs, operatorSet.id));
        operatorSetMembership[operator][operatorSetKey] = registered;
        registrationStatus[operator][operatorSetKey] = RegistrationStatus({
            registered: registered,
            slashableUntil: registered ? type(uint32).max : uint32(block.number) + DEALLOCATION_DELAY
        });
    }

    function setMaxMagnitude(address operator, IStrategy strategy, uint64 magnitude) external {
        maxMagnitudes[operator][strategy] = magnitude;
    }

    function setAllocation(
        address operator,
        OperatorSet memory operatorSet,
        IStrategy strategy,
        uint64 magnitude
    ) external {
        bytes32 operatorSetKey = keccak256(abi.encodePacked(operatorSet.avs, operatorSet.id));
        allocations[operator][operatorSetKey][strategy].currentMagnitude = magnitude;
        allocations[operator][operatorSetKey][strategy].effectBlock = uint32(block.number);
    }
}

/// @title Mock DelegationManager for PoC Testing
contract MockDelegationManager is Test {
    mapping(address => mapping(IStrategy => uint256)) public operatorShares;
    mapping(address => address) public delegatedTo;

    function slashOperatorShares(
        address operator,
        OperatorSet memory,
        uint256,
        IStrategy strategy,
        uint64 prevMaxMagnitude,
        uint64 newMaxMagnitude
    ) external returns (uint256) {
        uint256 currentShares = operatorShares[operator][strategy];
        uint256 slashedShares = (currentShares * (prevMaxMagnitude - newMaxMagnitude)) / prevMaxMagnitude;
        operatorShares[operator][strategy] -= slashedShares;
        return slashedShares;
    }

    function getOperatorShares(address operator, IStrategy[] memory strategies) external view returns (uint256[] memory) {
        uint256[] memory shares = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            shares[i] = operatorShares[operator][strategies[i]];
        }
        return shares;
    }

    function setOperatorShares(address operator, IStrategy strategy, uint256 shares) external {
        operatorShares[operator][strategy] = shares;
    }

    function delegateTo(address operator, string memory, string memory) external {
        delegatedTo[msg.sender] = operator;
    }
}

/// @title Mock StrategyManager for PoC Testing
contract MockStrategyManager is Test {
    mapping(address => mapping(IStrategy => uint256)) public stakerDepositShares;

    function depositIntoStrategy(IStrategy strategy, IERC20 token, uint256 amount) external returns (uint256) {
        stakerDepositShares[msg.sender][strategy] += amount;
        return amount;
    }

    function setStakerDepositShares(address staker, IStrategy strategy, uint256 shares) external {
        stakerDepositShares[staker][strategy] = shares;
    }
}

/// @title Mock Strategy for PoC Testing
contract MockStrategy is IStrategy, Test {
    IERC20 public token;
    mapping(address => uint256) public balances;

    constructor(IERC20 _token) {
        token = _token;
    }

    function deposit(IERC20, uint256 amount) external returns (uint256) {
        balances[msg.sender] += amount;
        return amount;
    }

    function withdraw(address, uint256 amount) external returns (uint256) {
        balances[msg.sender] -= amount;
        return amount;
    }
}

// Helper library for array operations
library ArrayLib {
    function toArrayU256(uint256 value) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = value;
        return arr;
    }

    function toArrayU32(uint32 value) internal pure returns (uint32[] memory) {
        uint32[] memory arr = new uint32[](1);
        arr[0] = value;
        return arr;
    }

    function toArrayU64(uint64 value, uint256 length) internal pure returns (uint64[] memory) {
        uint64[] memory arr = new uint64[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = value;
        }
        return arr;
    }
}
