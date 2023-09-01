// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Morpho} from "morpho-blue/Morpho.sol";

contract MorphoMock is Morpho {
    constructor(address newOwner) Morpho(newOwner) {}
}
