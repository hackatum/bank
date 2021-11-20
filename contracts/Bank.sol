//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IPriceOracle.sol";

contract Bank is IBank {
    address private oracle;
    address private hakToken;
    address private magic_token = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct Balance {
        mapping(address => uint256) tokens;
        uint256 eth_amount;
    }

    mapping(address => Balance) private accounts;

    constructor(address _priceOracle, address _hakToken) {
        oracle = _priceOracle;
        hakToken = _hakToken;
    }

    function isValidContract(address _addr)
        private
        view
        returns (bool isContract)
    {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function deposit(address token, uint256 amount)
        external
        payable
        override
        returns (bool)
    {
        // check for negative or 0
        if (token == magic_token) {
            accounts[msg.sender].eth_amount =
                accounts[msg.sender].eth_amount +
                amount;
            return true;
        } else {
            if (isValidContract(token) == false) {
                revert("token not supported");
            }
            IERC20 iecr20 = IERC20(token);
            if (iecr20.allowance(msg.sender, address(this)) < amount) {
                return false;
            }
            // Only set this value if money substraction was successful

            accounts[msg.sender].tokens[token] =
                accounts[msg.sender].tokens[token] +
                amount;
            return
                IERC20(token).transferFrom(msg.sender, address(this), amount);
        }

        // emit Deposit(msg.sender, token, amount);
        // return true;
    }

    function getBalance(address token) public view override returns (uint256) {
        // todo check if key is present in map
        if (token == magic_token) {
            return accounts[msg.sender].eth_amount;
        } else {
            return accounts[msg.sender].tokens[token];
        }
    }

    function withdraw(address token, uint256 amount)
        external
        override
        returns (uint256)
    {}

    function borrow(address token, uint256 amount)
        external
        override
        returns (uint256)
    {}

    function repay(address token, uint256 amount)
        external
        payable
        override
        returns (uint256)
    {}

    function liquidate(address token, address account)
        external
        payable
        override
        returns (bool)
    {}

    function getCollateralRatio(address token, address account)
        public
        view
        override
        returns (uint256)
    {}
}
