// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library ErrorsLib {
    string internal constant MAX_INT128_EXCEEDED = "max int128 exceeded";
    string internal constant INPUT_TOO_LARGE = "input too large";
    string internal constant WEXP_UNDERFLOW = "wExp underflow";
    string internal constant WEXP_OVERFLOW = "wExp overflow";
    string internal constant NOT_MORPHO = "not Morpho";
}
