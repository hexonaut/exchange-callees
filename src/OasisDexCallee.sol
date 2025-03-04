// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2020 Maker Ecosystem Growth Holdings, INC.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.6.12;

interface VatLike {
    function hope(address) external;
}

interface GemJoinLike {
    function dec() external view returns (uint256);
    function gem() external view returns (TokenLike);
    function exit(address, uint256) external;
}

interface DaiJoinLike {
    function dai() external view returns (TokenLike);
    function vat() external view returns (VatLike);
    function join(address, uint256) external;
}

interface TokenLike {
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
}

interface OtcLike {
    function buyAllAmount(address, uint256, address, uint256) external returns (uint256);
    function sellAllAmount(address, uint256, address, uint256) external returns (uint256);
}

// Simple Callee Example to interact with MatchingMarket
// This Callee contract exists as a standalone contract
contract CalleeMakerOtc {
    OtcLike         public otc;
    DaiJoinLike     public daiJoin;
    TokenLike       public dai;

    uint256         public constant RAY = 10 ** 27;

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }

    function setUp(address otc_, address clip_, address daiJoin_) internal {
        otc = OtcLike(otc_);
        daiJoin = DaiJoinLike(daiJoin_);
        dai = daiJoin.dai();


        daiJoin.vat().hope(clip_);

        dai.approve(daiJoin_, uint256(-1));
    }

    function _fromWad(address gemJoin, uint256 wad) internal view returns (uint256 amt) {
        amt = wad / 10 ** (sub(18, GemJoinLike(gemJoin).dec()));
    }
}

// Maker-Otc is MatchingMarket, which is the core contract of OasisDex
contract CalleeMakerOtcDai is CalleeMakerOtc {
    constructor(address otc_, address clip_, address daiJoin_) public {
        setUp(otc_, clip_, daiJoin_);
    }

    function clipperCall(
        address sender,         // Clipper Caller and Dai deliveryaddress
        uint256 daiAmt,         // Dai amount to payback[rad]
        uint256 gemAmt,         // Gem amount received [wad]
        bytes calldata data     // Extra data needed (gemJoin)
    ) external {
        // Get address to send remaining DAI, gemJoin adapter and minProfit in DAI to make
        (address to, address gemJoin, uint256 minProfit) = abi.decode(data, (address, address, uint256));

        // Convert gem amount to token precision
        gemAmt = _fromWad(gemJoin, gemAmt);

        // Exit collateral to token version
        GemJoinLike(gemJoin).exit(address(this), gemAmt);

        // Approve otc to take gem
        TokenLike gem = GemJoinLike(gemJoin).gem();
        gem.approve(address(otc), gemAmt);

        // Calculate amount of DAI to Join (as erc20 WAD value)
        uint256 daiToJoin = divup(daiAmt, RAY);

        // Do operation and get dai amount bought (checking the profit is achieved)
        uint256 daiBought = otc.sellAllAmount(address(gem), gemAmt, address(dai), add(daiToJoin, minProfit));

        // Although maker-otc reverts if order book is empty, this check is a sanity check for other exchnages
        // Transfer any lingering gem to specified address
        if (gem.balanceOf(address(this)) > 0) {
            gem.transfer(to, gem.balanceOf(address(this)));
        }

        // Convert DAI bought to internal vat value of the msg.sneder of Clipper.take
        daiJoin.join(sender, daiToJoin);

        // Transfer remaining DAI to specified address
        dai.transfer(to, dai.balanceOf(address(this)));
    }
}

// Maker-Otc is MatchingMarket, which is the core contract of OasisDex
/* contract CalleeMakerOtcGem is CalleeMakerOtc {
    constructor(address otc_, address clip_, address daiJoin_) public {
        setUp(otc_, clip_, daiJoin_);
    }

    function clipperCall(
        uint256 daiAmt,         // Dai amount to payback[rad]
        uint256 gemAmt,         // Gem amount received [wad]
        bytes calldata data     // Extra data needed (gemJoin)
    ) external {
        // Get address to send remaining Gem, gemJoin adapter and minProfit in Gem to make
        (address to, address gemJoin, uint256 minProfit) = abi.decode(data, (address, address, uint256));

        // Convert gem amount to token precision
        gemAmt = _fromWad(gemJoin, gemAmt);

        // Exit collateral to token version
        GemJoinLike(gemJoin).exit(address(this), gemAmt);

        // Approve otc to take gem
        TokenLike gem = GemJoinLike(gemJoin).gem();
        gem.approve(address(otc), gemAmt);

        // Calculate amount of DAI to Join (as erc20 WAD value)
        uint256 daiToJoin = daiAmt / RAY;
        if (daiToJoin * RAY < daiAmt) {
            daiToJoin = daiToJoin + 1;
        }

        // Do operation and get gem amount sold (checking the profit is achieved)
        uint256 gemSold = otc.buyAllAmount(address(dai), daiToJoin, address(gem), gemAmt - minProfit);
        // TODO: make sure daiToJoin is actually the amount received from buyAllAmount (due rounding)

        // Convert DAI bought to internal vat value
        daiJoin.join(address(this), daiToJoin);

        // Transfer remaining gem to specified address
        gem.transfer(to, gemAmt - gemSold);
    }
} */
