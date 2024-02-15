// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IIrm} from "../../lib/morpho-blue/src/interfaces/IIrm.sol";
import {Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

/// @title IFixedRateIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.org
interface IFixedRateIrm is IIrm {
    function borrowRateStored(Id id) external returns (uint256);
    function setBorrowRate(Id id, uint256 newBorrowRate) external;
}
