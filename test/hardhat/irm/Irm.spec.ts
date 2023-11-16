import { AbiCoder, MaxUint256, keccak256, toBigInt } from "ethers";
import hre from "hardhat";
import _range from "lodash/range";
import { ERC20Mock, AdaptativeCurveIrm, MorphoMock, OracleMock } from "types";
import { MarketParamsStruct } from "types/src/mocks/MorphoMock";

import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { setNextBlockTimestamp } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time";

// Without the division it overflows.
const initBalance = MaxUint256 / 10000000000000000n;
const oraclePriceScale = 1000000000000000000000000000000000000n;

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

  await setNextBlockTimestamp(block!.timestamp + elapsed);
};

describe("irm", () => {
  let admin: SignerWithAddress;
  let suppliers: SignerWithAddress[];
  let borrowers: SignerWithAddress[];

  let morpho: MorphoMock;
  let borrowable: ERC20Mock;
  let collateral: ERC20Mock;
  let oracle: OracleMock;
  let irm: AdaptativeCurveIrm;

  let marketParams: MarketParamsStruct;
  let id: Buffer;

  const updateMarket = (newMarket: Partial<MarketParamsStruct>) => {
    marketParams = { ...marketParams, ...newMarket };
    id = identifier(marketParams);
  };

  beforeEach(async () => {
    const allSigners = await hre.ethers.getSigners();

    const users = allSigners.slice(0, -1);

    [admin] = allSigners.slice(-1);
    suppliers = users.slice(0, users.length / 2);
    borrowers = users.slice(users.length / 2);

    const ERC20MockFactory = await hre.ethers.getContractFactory("ERC20Mock", admin);

    borrowable = await ERC20MockFactory.deploy("DAI", "DAI");
    collateral = await ERC20MockFactory.deploy("Wrapped BTC", "WBTC");

    const OracleMockFactory = await hre.ethers.getContractFactory("OracleMock", admin);

    oracle = await OracleMockFactory.deploy();

    await oracle.setPrice(oraclePriceScale);

    const MorphoFactory = await hre.ethers.getContractFactory("MorphoMock", admin);

    morpho = await MorphoFactory.deploy(admin.address);

    const morphoAddress = await morpho.getAddress();

    const AdaptativeCurveIrmFactory = await hre.ethers.getContractFactory("AdaptativeCurveIrm", admin);

    irm = await AdaptativeCurveIrmFactory.deploy(
      morphoAddress,
      4000000000000000000n,
      1585489599188n,
      900000000000000000n,
      317097919n,
    );

    const borrowableAddress = await borrowable.getAddress();
    const collateralAddress = await collateral.getAddress();
    const oracleAddress = await oracle.getAddress();
    const irmAddress = await irm.getAddress();

    updateMarket({
      loanToken: borrowableAddress,
      collateralToken: collateralAddress,
      oracle: oracleAddress,
      irm: irmAddress,
      lltv: BigInt.WAD / 2n + 1n,
    });

    await morpho.enableLltv(marketParams.lltv);
    await morpho.enableIrm(marketParams.irm);
    await morpho.createMarket(marketParams);

    for (const user of users) {
      await borrowable.setBalance(user.address, initBalance);
      await borrowable.connect(user).approve(morphoAddress, MaxUint256);
      await collateral.setBalance(user.address, initBalance);
      await collateral.connect(user).approve(morphoAddress, MaxUint256);
    }

    hre.tracer.nameTags[morphoAddress] = "Morpho";
    hre.tracer.nameTags[collateralAddress] = "Collateral";
    hre.tracer.nameTags[borrowableAddress] = "Borrowable";
    hre.tracer.nameTags[oracleAddress] = "Oracle";
    hre.tracer.nameTags[irmAddress] = "IRM";
  });

  it("should simulate gas cost [main]", async () => {
    for (let i = 0; i < suppliers.length; ++i) {
      logProgress("main", i, suppliers.length);

      const supplier = suppliers[i];

      let assets = BigInt.WAD * toBigInt(1 + Math.floor(random() * 100));

      await randomForwardTimestamp();

      await morpho.connect(supplier).supply(marketParams, assets, 0, supplier.address, "0x");

      await randomForwardTimestamp();

      await morpho.connect(supplier).withdraw(marketParams, assets / 2n, 0, supplier.address, supplier.address);

      const borrower = borrowers[i];

      const market = await morpho.market(id);
      const liquidity = market.totalSupplyAssets - market.totalBorrowAssets;

      assets = assets.min(liquidity / 2n);

      await randomForwardTimestamp();

      await morpho.connect(borrower).supplyCollateral(marketParams, assets, borrower.address, "0x");

      await randomForwardTimestamp();

      await morpho.connect(borrower).borrow(marketParams, assets / 2n, 0, borrower.address, borrower.address);

      await randomForwardTimestamp();

      await morpho.connect(borrower).repay(marketParams, assets / 4n, 0, borrower.address, "0x");

      await randomForwardTimestamp();

      await morpho.connect(borrower).withdrawCollateral(marketParams, assets / 8n, borrower.address, borrower.address);
    }
  });

  it("should trace borrow rate [borrowRate]", async () => {
    const supplier = suppliers[0];

    await morpho.connect(supplier).supply(marketParams, BigInt.WAD, 0, supplier.address, "0x");

    const borrower = borrowers[0];

    await morpho.connect(borrower).supplyCollateral(marketParams, BigInt.WAD, borrower.address, "0x");
    await morpho.connect(borrower).borrow(marketParams, BigInt.WAD / 2n, 0, borrower.address, borrower.address);

    const block = await hre.ethers.provider.getBlock("latest");
    await setNextBlockTimestamp(block!.timestamp + 60 * 60 * 24);

    hre.tracer.printNext = true;
    hre.tracer.enableAllOpcodes = true;
    await morpho.accrueInterest(marketParams);
  });
});
