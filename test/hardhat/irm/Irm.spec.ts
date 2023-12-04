import { AbiCoder, keccak256, toBigInt } from "ethers";
import hre from "hardhat";
import _range from "lodash/range";
import { AdaptiveCurveIrm } from "types";
import { MarketParamsStruct } from "types/lib/morpho-blue/src/interfaces/IIrm";

import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { setNextBlockTimestamp } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time";

let seed = 42;
const random = () => {
  seed = (seed * 16807) % 2147483647;

  return (seed - 1) / 2147483646;
};

const identifier = (marketParams: MarketParamsStruct) => {
  const encodedMarket = AbiCoder.defaultAbiCoder().encode(
    ["address", "address", "address", "address", "uint256"],
    Object.values(marketParams),
  );

  return Buffer.from(keccak256(encodedMarket).slice(2), "hex");
};

const logProgress = (name: string, i: number, max: number) => {
  if (i % 10 == 0) console.log("[" + name + "]", Math.floor((100 * i) / max), "%");
};

const randomForwardTimestamp = async () => {
  const block = await hre.ethers.provider.getBlock("latest");
  const elapsed = random() < 1 / 2 ? 0 : (1 + Math.floor(random() * 100)) * 12; // 50% of the time, don't go forward in time.

  const newTimestamp = block!.timestamp + elapsed;

  await setNextBlockTimestamp(block!.timestamp + elapsed);

  return newTimestamp;
};

describe("irm", () => {
  let admin: SignerWithAddress;

  let irm: AdaptiveCurveIrm;

  let marketParams: MarketParamsStruct;

  beforeEach(async () => {
    [admin] = await hre.ethers.getSigners();

    const AdaptiveCurveIrmFactory = await hre.ethers.getContractFactory("AdaptiveCurveIrm", admin);

    irm = await AdaptiveCurveIrmFactory.deploy(
      await admin.getAddress(),
      4000000000000000000n,
      1585489599188n,
      900000000000000000n,
      317097919n,
    );

    const irmAddress = await irm.getAddress();

    marketParams = {
      // Non-zero address to include calldata gas cost.
      collateralToken: irmAddress,
      loanToken: irmAddress,
      oracle: irmAddress,
      irm: irmAddress,
      lltv: 0,
    };

    hre.tracer.nameTags[irmAddress] = "IRM";
  });

  it("should simulate gas cost [main]", async () => {
    for (let i = 0; i < 200; ++i) {
      logProgress("main", i, 200);

      const lastUpdate = await randomForwardTimestamp();

      const totalSupplyAssets = BigInt.WAD * toBigInt(1 + Math.floor(random() * 100));
      const totalBorrowAssets = totalSupplyAssets.wadMul(toBigInt(Math.floor(random() * 1e18)));

      await irm.borrowRate(marketParams, {
        fee: 0,
        lastUpdate,
        totalSupplyAssets: totalSupplyAssets,
        totalBorrowAssets: totalBorrowAssets,
        // Non-zero shares to include calldata gas cost.
        totalSupplyShares: 1000000000000n,
        totalBorrowShares: 1000000000000n,
      });
    }
  });
});
