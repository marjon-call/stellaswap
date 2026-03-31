# Out of Scope

## Vulnerability Types Excluded

- Best practice critiques and recommendations
- Feature requests
- Incorrect data supplied by third-party oracles (excluding oracle manipulation/flash loan attacks)
- Impacts requiring basic economic and governance attacks (e.g., 51% attack)
- Lack of liquidity impacts
- Impacts from Sybil attacks
- Impacts involving centralization risks
- Attacks already exploited by the reporter causing damage
- Impacts from leaked keys/credentials
- Privileged address access without additional modifications to the access control
- External stablecoin depegging without a direct code bug as the cause
- Phishing or social engineering attacks
- Test file and configuration file impacts

## Previously Audited Issues

Issues identified in these prior audits are out of scope:
- Certik Full Audit Report
- SolidProof Smart Contract Audit
- SolidProof Stable AMM Audit Report
- ABDK Consulting Algebra Audit
- Hexen Algebra Audit
- Code4rena QuickSwap/StellaSwap Contest
- Mixbytes stDOT Audit
- PeckShield stDOT Audit
- SolidProof stDOT Audit
- AstraSec stGLMR Audit

## Submission Rules

- Proof of Concept is required for all submissions
- All bug reports must include a suggested fix
- Testing must use local forks only (no mainnet/testnet interactions)
- No third-party oracle or smart contract testing
