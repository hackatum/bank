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

    function isValidContract(address token)
        private
        view
        returns (bool isContract)
    {
        uint32 size;
        assembly {
            size := extcodesize(token)
        }
        return (size > 0);
    }

    modifier OnlyIfValidToken(address token) {
        if (token != magic_token && isValidContract(token) == false) {
            revert("token not supported");
        }
        _;
    }

    function deposit(address token, uint256 amount)
        external
        payable
        override
        OnlyIfValidToken(token)
        returns (bool)
    {
        // TODO: check for negative or 0
        if (token == magic_token) {
            accounts[msg.sender].eth_amount =
                accounts[msg.sender].eth_amount +
                amount;
            return true;
        } else {
            IERC20 iecr20 = IERC20(token);
            if (iecr20.allowance(msg.sender, address(this)) < amount) {
                return false;
            }
            // TODO: Only set this value if money substraction was successful
            // TODO: Add thread safety. Should we????
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

    function check_balance(uint256 cur_balance, uint256 to_withdraw)
        private
        pure
    {
        if (cur_balance == 0) {
            revert("no balance");
        }
        if (cur_balance < to_withdraw) {
            revert("amount exceeds balance");
        }
    }

    function withdraw(address token, uint256 amount)
        external
        override
        OnlyIfValidToken(token)
        returns (uint256)
    {
        // TODO: Check negative
        // TODO: Check can not withdraw more than balance

        uint256 to_withdraw = 0;
        if (token == magic_token) {
            if (amount == 0) {
                // if zero, then we withdraw all the money
                to_withdraw = accounts[msg.sender].eth_amount;
            } else {
                to_withdraw = amount;
            }
            // TODO: make thread safe
            uint256 cur_balance = accounts[msg.sender].eth_amount;
            check_balance(cur_balance, to_withdraw);

            accounts[msg.sender].eth_amount =
                accounts[msg.sender].eth_amount -
                to_withdraw;

            return cur_balance;
        } else {
            if (amount == 0) {
                // if zero, then we withdraw all the money
                to_withdraw = accounts[msg.sender].tokens[token];
            } else {
                to_withdraw = amount;
            }

            // TODO: make thread safe
            uint256 cur_balance = accounts[msg.sender].tokens[token];
            check_balance(cur_balance, to_withdraw);

            accounts[msg.sender].tokens[token] =
                accounts[msg.sender].tokens[token] -
                to_withdraw;

            return cur_balance;
        }
    }

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
