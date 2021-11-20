//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/Math.sol";
import "hardhat/console.sol";

contract Bank is IBank {
    IPriceOracle oracle;
    address private hakToken;
    address private magic_token = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct Balance {
        address[] token_address_list;
        Account[] borrow_list;
        mapping(address => Account) tokens_map;
        // mapping(address => Account) borrows_map;
        uint256 collateral;
        Account eth_act;
    }

    mapping(address => Balance) private accounts;

    constructor(address _priceOracle, address _hakToken) {
        oracle = IPriceOracle(_priceOracle);
        hakToken = _hakToken;
    }

    function updateBorrowInterest() private returns (uint256) {
        Balance storage user_bal = accounts[msg.sender];
        uint256 total = 0;
        uint256 arrayLength = user_bal.borrow_list.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            Account memory updated_token_acc = calculateInterest(
                user_bal.borrow_list[i],
                block.number,
                5
            );
            user_bal.borrow_list[i] = updated_token_acc;
            total =
                total +
                updated_token_acc.deposit +
                updated_token_acc.interest;
        }

        return total;
    }

    modifier updateInterest(address token) {
        Balance storage user_bal = accounts[msg.sender];

        Account memory updated_eth_acc = calculateInterest(
            user_bal.eth_act,
            block.number,
            3
        );
        accounts[msg.sender].eth_act = updated_eth_acc;

        uint256 arrayLength = user_bal.token_address_list.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            Account memory updated_token_acc = calculateInterest(
                user_bal.tokens_map[user_bal.token_address_list[i]],
                block.number,
                3
            );
            user_bal.tokens_map[
                user_bal.token_address_list[i]
            ] = updated_token_acc;
            //   totalValue += mappedUsers[addressIndices[i]];
        }
        _;
    }

    // TODO: maybe we can use calldata instead of memory
    function calculateInterest(
        Account memory account,
        uint256 current_block,
        uint256 interest
    ) private view returns (Account memory) {
        uint256 passed_block = current_block - account.lastInterestBlock;
        if (passed_block < 0) revert("Can not go back to past");
        uint256 tem = DSMath.mul(interest, passed_block);
        // uint256 amt_interest = ((3 * passed_block) / 10000); // TODO: Recheck // .03

        uint256 added_interest = DSMath.mul(account.deposit, tem) / 10000;
        // revert(added_interest);
        return
            Account(
                account.deposit,
                account.interest + added_interest,
                current_block
            );
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
        updateInterest(token)
        returns (bool)
    {
        // TODO: check for negative or 0
        if (token == magic_token) {
            accounts[msg.sender].eth_act.deposit =
                accounts[msg.sender].eth_act.deposit +
                amount;

            if (accounts[msg.sender].eth_act.lastInterestBlock == 0) {
                accounts[msg.sender].eth_act.lastInterestBlock = block.number;
            }

            return true;
        } else {
            IERC20 iecr20 = IERC20(token);
            if (iecr20.allowance(msg.sender, address(this)) < amount) {
                return false;
            }
            // TODO: Only set this value if money substraction was successful
            // TODO: Add thread safety. Should we????
            accounts[msg.sender].token_address_list.push(token);
            accounts[msg.sender].tokens_map[token].deposit =
                accounts[msg.sender].tokens_map[token].deposit +
                amount;

            if (accounts[msg.sender].tokens_map[token].lastInterestBlock == 0) {
                accounts[msg.sender].tokens_map[token].lastInterestBlock = block
                    .number;
            }
            return
                IERC20(token).transferFrom(msg.sender, address(this), amount);
        }

        // emit Deposit(msg.sender, token, amount);
        // return true;
    }

    function getBalance(address token) public view override returns (uint256) {
        // todo check if key is present in map
        if (token == magic_token) {
            Account memory updated = calculateInterest(
                accounts[msg.sender].eth_act,
                block.number,
                3
            );
            return updated.deposit + updated.interest;
        } else {
            Account memory updated = calculateInterest(
                accounts[msg.sender].tokens_map[token],
                block.number,
                3
            );
            return updated.deposit + updated.interest;
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

    //TODO: Check interest
    function withdraw(address token, uint256 amount)
        external
        override
        OnlyIfValidToken(token)
        updateInterest(token)
        returns (uint256)
    {
        // TODO: Check negative
        // TODO: Check can not withdraw more than balance

        uint256 to_withdraw = 0;
        if (token == magic_token) {
            if (amount == 0) {
                // if zero, then we withdraw all the money
                to_withdraw =
                    accounts[msg.sender].eth_act.deposit +
                    accounts[msg.sender].eth_act.interest;
            } else {
                to_withdraw = amount;
            }
            // TODO: make thread safe
            uint256 cur_balance = accounts[msg.sender].eth_act.deposit +
                accounts[msg.sender].eth_act.interest;
            check_balance(cur_balance, to_withdraw);

            if (to_withdraw <= accounts[msg.sender].eth_act.interest) {
                accounts[msg.sender].eth_act.interest =
                    accounts[msg.sender].eth_act.interest -
                    to_withdraw;
            } else {
                accounts[msg.sender].eth_act.deposit =
                    accounts[msg.sender].eth_act.deposit -
                    (to_withdraw - accounts[msg.sender].eth_act.interest);
                accounts[msg.sender].eth_act.interest = 0;
            }
            emit Withdraw(msg.sender, token, to_withdraw);
            return to_withdraw;
        } else {
            if (amount == 0) {
                // if zero, then we withdraw all the money
                to_withdraw =
                    accounts[msg.sender].tokens_map[token].deposit +
                    accounts[msg.sender].tokens_map[token].interest;
            } else {
                to_withdraw = amount;
            }

            // TODO: make thread safe
            uint256 cur_balance = accounts[msg.sender]
                .tokens_map[token]
                .deposit + accounts[msg.sender].tokens_map[token].interest;
            check_balance(cur_balance, to_withdraw);

            if (
                to_withdraw <= accounts[msg.sender].tokens_map[token].interest
            ) {
                accounts[msg.sender].tokens_map[token].interest =
                    accounts[msg.sender].tokens_map[token].interest -
                    to_withdraw;
            } else {
                accounts[msg.sender].tokens_map[token].deposit =
                    accounts[msg.sender].tokens_map[token].deposit -
                    (to_withdraw -
                        accounts[msg.sender].tokens_map[token].interest);
                accounts[msg.sender].tokens_map[token].interest = 0;
            }
            emit Withdraw(msg.sender, token, to_withdraw);
            return to_withdraw;
        }
    }

    function borrow(address token, uint256 amount)
        external
        override
        OnlyIfValidToken(token)
        updateInterest(token)
        returns (uint256)
    {
        if (token != magic_token) {
            revert("");
        }
        if (accounts[msg.sender].token_address_list.length == 0) {
            revert("no collateral deposited");
        }

        uint256 cur_balance = 0;
        Balance storage user_bal = accounts[msg.sender];
        uint256 arrayLength = user_bal.token_address_list.length;

        for (uint256 i = 0; i < arrayLength; i++) {
            cur_balance =
                cur_balance +
                user_bal.tokens_map[user_bal.token_address_list[i]].deposit +
                user_bal.tokens_map[user_bal.token_address_list[i]].interest;
        }

        Account memory borrow_item = Account(amount, 0, block.number);
        user_bal.borrow_list.push(borrow_item);
        user_bal.collateral = (cur_balance * 10000) / updateBorrowInterest();

        emit Borrow(msg.sender, token, amount, user_bal.collateral);

        return user_bal.collateral;
    }

    function repay(address token, uint256 amount)
        external
        payable
        override
        OnlyIfValidToken(token)
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
    {
        return accounts[msg.sender].collateral;
    }
}
