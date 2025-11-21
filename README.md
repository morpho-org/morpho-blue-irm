# Morpho Blue IRMs

Some interest rate models for Morpho Blue:

- [AdaptiveCurveIRM](src/adaptive-curve-irm/AdaptiveCurveIrm.sol)
  - _Important_: The `AdaptiveCurveIRM` was deployed [on Ethereum](https://etherscan.io/address/0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC) without the `via_ir` solc compilation option.
    To check the bytecode on Ethereum, disable `via_ir` in `foundry.toml`.
    Other deployments use `via_ir`.
- [FixedRateIRM](src/fixed-rate-irm/FixedRateIrm.sol)

## Resources

- AdaptiveCurveIRM: [documentation](https://docs.morpho.org/concepts/morpho-blue/core-concepts/irm#the-adaptivecurveirm), [announcement article](https://morpho.mirror.xyz/aaUjIF85aIi5RT6-pLhVWBzuiCpOb4BV03OYNts2BHQ).

## Audits

All audits are stored in the [audits](audits)' folder.

## Getting started

Compilation, testing and formatting with [forge](https://book.getfoundry.sh/getting-started/installation).

## Licenses

The primary license is MIT, see [LICENSE](LICENSE).
