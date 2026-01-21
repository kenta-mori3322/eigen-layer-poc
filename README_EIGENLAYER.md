# EigenLayer AllocationManager Vulnerability PoC

**⚠️ IMPORTANT: This PoC uses MOCK contracts only - it does NOT interact with production EigenLayer contracts.**

This PoC demonstrates **4 vulnerabilities** in the EigenLayer `AllocationManager` contract following the Immunefi forge-poc-templates structure. All tests run in a controlled mock environment.

## Vulnerabilities Demonstrated

1. **No On-Chain Validation of Misbehavior** 🔴 HIGH
   - Slashers can slash operators without providing on-chain proof
   - Test: `testAttack_VULN1_NoOnChainValidation()`

2. **Deregistration Delay Window** 🔴 HIGH
   - Operators remain slashable for 14 days after deregistration
   - Test: `testAttack_VULN2_DeregistrationDelayWindow()`

3. **No Appeal Mechanism** 🔴 HIGH
   - Slashing is completely irreversible
   - Test: `testAttack_VULN3_NoAppealMechanism()`

4. **Rounding Up Can Cause Over-Slashing** 🟡 MEDIUM
   - `mulWadRoundUp()` causes slight over-slashing
   - Test: `testAttack_VULN4_RoundingUpOverSlashing()`

## Setup

### Prerequisites

Install Foundry: https://book.getfoundry.sh/getting-started/installation

### Mock Environment

This PoC uses **mock contracts** to demonstrate vulnerabilities in a controlled environment:

- **MockAllocationManager**: Simulates AllocationManager behavior
- **MockDelegationManager**: Simulates DelegationManager behavior  
- **MockStrategyManager**: Simulates StrategyManager behavior
- **MockStrategy**: Simulates a strategy contract

**No production contracts are used** - all tests run against mocks deployed in the test environment.

## Running the PoC

### Run all tests:
```bash
forge test -vv --match-path test/pocs/EigenLayerSlashingPoC.t.sol
```

### Run individual vulnerability tests:
```bash
# Vulnerability #1
forge test -vv --match-test testAttack_VULN1_NoOnChainValidation

# Vulnerability #2
forge test -vv --match-test testAttack_VULN2_DeregistrationDelayWindow

# Vulnerability #3
forge test -vv --match-test testAttack_VULN3_NoAppealMechanism

# Vulnerability #4
forge test -vv --match-test testAttack_VULN4_RoundingUpOverSlashing
```

## Expected Output

Each test will:
1. Print initial state (operator magnitude, delegator shares)
2. Execute the attack
3. Print final state showing the vulnerability
4. Display profit/loss using the `snapshot` modifier

Example output:
```
=== VULNERABILITY #1: No On-Chain Validation of Misbehavior ===

Initial State:
  Operator Magnitude: 1000000000000000000
  Operator Max Magnitude: 1000000000000000000

[ATTACK] Legitimate slasher slashes operator with 50% WITHOUT providing on-chain proof

After Slash:
  Operator Magnitude: 500000000000000000
  Operator Max Magnitude: 500000000000000000

[VULNERABILITY CONFIRMED] Slasher can slash without on-chain proof
  Operator maxMagnitude permanently reduced by: 500000000000000000
```

## Notes

- **This PoC uses MOCK contracts only** - it does NOT interact with production EigenLayer contracts
- All tests run in a controlled mock environment
- The vulnerabilities are demonstrated using simplified mock implementations that replicate the vulnerable behavior
- This approach is safe and acceptable for security research

## Mock Contracts

Mock contracts are located in `src/mocks/eigenlayer/EigenLayerMocks.sol`:
- `MockAllocationManager`: Implements the vulnerable slashing logic
- `MockDelegationManager`: Tracks operator shares
- `MockStrategyManager`: Tracks staker deposit shares
- `MockStrategy`: Simple strategy implementation

## References

- Immunefi Template: https://github.com/immunefi-team/forge-poc-templates
- EigenLayer Contracts: https://github.com/Layr-Labs/eigenlayer-contracts
