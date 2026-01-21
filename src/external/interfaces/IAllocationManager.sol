// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Simplified interface for AllocationManager - only functions needed for PoC
// Full interface available at: https://github.com/Layr-Labs/eigenlayer-contracts

import "forge-std/interfaces/IERC20.sol";

interface IStrategy {
    function deposit(IERC20 token, uint256 amount) external returns (uint256);
}

struct OperatorSet {
    address avs;
    uint32 id;
}

struct SlashingParams {
    address operator;
    uint32 operatorSetId;
    IStrategy[] strategies;
    uint256[] wadsToSlash;
    string description;
}

struct AllocateParams {
    OperatorSet operatorSet;
    IStrategy[] strategies;
    uint64[] newMagnitudes;
}

struct DeregisterParams {
    address operator;
    address avs;
    uint32[] operatorSetIds;
}

struct CreateSetParamsV2 {
    uint32 operatorSetId;
    IStrategy[] strategies;
    address slasher;
}

struct Allocation {
    uint64 currentMagnitude;
    int128 pendingDiff;
    uint32 effectBlock;
}

interface IAllocationManager {
    function slashOperator(
        address avs,
        SlashingParams calldata params
    ) external returns (uint256 slashId, uint256[] memory shares);

    function modifyAllocations(
        address operator,
        AllocateParams[] calldata params
    ) external;

    function deregisterFromOperatorSets(
        DeregisterParams calldata params
    ) external;

    function createOperatorSets(
        address avs,
        CreateSetParamsV2[] calldata params
    ) external;

    function updateAVSMetadataURI(
        address avs,
        string calldata metadataURI
    ) external;

    function getAllocation(
        address operator,
        OperatorSet memory operatorSet,
        IStrategy strategy
    ) external view returns (Allocation memory);

    function getMaxMagnitudes(
        address operator,
        IStrategy[] memory strategies
    ) external view returns (uint256[] memory);

    function isOperatorSlashable(
        address operator,
        OperatorSet memory operatorSet
    ) external view returns (bool);

    function isMemberOfOperatorSet(
        address operator,
        OperatorSet memory operatorSet
    ) external view returns (bool);

    function DEALLOCATION_DELAY() external view returns (uint32);
}
