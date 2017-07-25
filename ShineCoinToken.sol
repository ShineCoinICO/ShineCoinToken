pragma solidity ^0.4.6;

contract SafeMath {
    function mul(uint a, uint b) internal returns (uint) {
        uint c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint a, uint b) internal returns (uint) {
        assert(b > 0);
        uint c = a / b;
        assert(a == b * c + a % b);
        return c;
    }

    function sub(uint a, uint b) internal returns (uint) {
        assert(b <= a);
        return a - b;
    }

    function add(uint a, uint b) internal returns (uint) {
        uint c = a + b;
        assert(c >= a);
        return c;
    }
}

contract TokenController {
    function proxyPayment(address _owner) payable returns (bool);

    function onTransfer(address _from, address _to, uint _amount) returns (bool);

    function onApprove(address _owner, address _spender, uint _amount)
    returns (bool);
}


contract Controlled {
    modifier onlyController {if (msg.sender != controller) throw;
        _;}

    address public controller;

    function Controlled() {controller = msg.sender;}

    function changeController(address _newController) onlyController {
        controller = _newController;
    }
}


contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 _amount, address _token, bytes _data);
}


contract ShineCoinToken is Controlled {
    string public name;
    uint8 public decimals;
    string public symbol;
    string public version = 'SHINE_0.1';

    struct Checkpoint {
        uint128 fromBlock;
        uint128 value;
    }

    ShineCoinToken public parentToken;

    address public frozenReserveTeamRecipient;

    uint public parentSnapShotBlock;

    uint public creationBlock;

    // Periods
    uint public firstRewardPeriodEndBlock;

    uint public secondRewardPeriodEndBlock;

    uint public thirdRewardPeriodEndBlock;

    uint public finalRewardPeriodEndBlock;

    // Loos
    uint public firstLoos;

    uint public secondLoos;

    uint public thirdLoos;

    uint public finalLoos;


    // Percents
    uint public firstRewardPeriodPercent;

    uint public secondRewardPeriodPercent;

    uint public thirdRewardPeriodPercent;

    uint public finalRewardPeriodPercent;

    // Unfreeze team wallet for transfers
    uint public unfreezeTeamRecepientBlock;

    mapping (address => Checkpoint[]) balances;

    mapping (address => mapping (address => uint256)) allowed;

    Checkpoint[] totalSupplyHistory;

    bool public transfersEnabled;

    ShineCoinTokenFactory public tokenFactory;

    function ShineCoinToken(
        address _tokenFactory,
        address _parentToken,
        uint _parentSnapShotBlock,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        bool _transfersEnabled
    ) {
        tokenFactory = ShineCoinTokenFactory(_tokenFactory);
        name = _tokenName;
        decimals = _decimalUnits;
        symbol = _tokenSymbol;
        parentToken = ShineCoinToken(_parentToken);
        parentSnapShotBlock = _parentSnapShotBlock;
        transfersEnabled = _transfersEnabled;
        creationBlock = block.number;
        unfreezeTeamRecepientBlock = block.number + ((396 * 24 * 3600) / 18); // 396 days

        firstRewardPeriodEndBlock = creationBlock + ((121 * 24 * 3600) / 18); // 121 days
        secondRewardPeriodEndBlock = creationBlock + ((181 * 24 * 3600) / 18); // 181 days
        thirdRewardPeriodEndBlock = creationBlock + ((211 * 24 * 3600) / 18); // 211 days
        finalRewardPeriodEndBlock = creationBlock + ((760 * 24 * 3600) / 18); // 2 years

        firstRewardPeriodPercent = 29;
        secondRewardPeriodPercent = 23;
        thirdRewardPeriodPercent = 18;
        finalRewardPeriodPercent = 12;

        firstLoos = ((15 * 24 * 3600) / 18); // 15 days;
        secondLoos = ((10 * 24 * 3600) / 18); // 10 days;
        thirdLoos = ((5 * 24 * 3600) / 18); // 5 days;
        finalLoos = ((1 * 24 * 3600) / 18); // 1 days;
    }

    function changeReserveTeamRecepient(address _newReserveTeamRecipient) onlyController returns (bool) {
        frozenReserveTeamRecipient = _newReserveTeamRecipient;
        return true;
    }

    ///////////////////
    // ERC20 Methods
    ///////////////////

    function transfer(address _to, uint256 _amount) returns (bool success) {
        if (!transfersEnabled) throw;
        if ((address(msg.sender) == frozenReserveTeamRecipient) && (block.number < unfreezeTeamRecepientBlock)) throw;
        if ((_to == frozenReserveTeamRecipient) && (block.number < unfreezeTeamRecepientBlock)) throw;
        return doTransfer(msg.sender, _to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) returns (bool success) {
        if (msg.sender != controller) {
            if (!transfersEnabled) throw;

            if (allowed[_from][msg.sender] < _amount) return false;
            allowed[_from][msg.sender] -= _amount;
        }
        return doTransfer(_from, _to, _amount);
    }

    function doTransfer(address _from, address _to, uint _amount) internal returns (bool) {

        if (_amount == 0) {
            return true;
        }

        if (parentSnapShotBlock >= block.number) throw;

        if ((_to == 0) || (_to == address(this))) throw;

        var previousBalanceFrom = balanceOfAt(_from, block.number);
        if (previousBalanceFrom < _amount) {
            return false;
        }

        if (isContract(controller)) {
            if (!TokenController(controller).onTransfer(_from, _to, _amount))
            throw;
        }

        Checkpoint[] checkpoints = balances[_from];
        uint lastBlock = checkpoints[checkpoints.length - 1].fromBlock;
        uint blocksFromLastBlock = block.number - lastBlock;
        uint rewardAmount = 0;

        if (block.number <= firstRewardPeriodEndBlock) {
            if (blocksFromLastBlock > firstLoos) {
                rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * blocksFromLastBlock;
            }
        }
        else if (block.number <= secondRewardPeriodEndBlock) {
            if (blocksFromLastBlock > secondLoos) {
                if (lastBlock < firstRewardPeriodEndBlock) {
                    rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * (firstRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * secondRewardPeriodPercent * (secondRewardPeriodEndBlock - block.number);
                }
                else {
                    rewardAmount = previousBalanceFrom * secondRewardPeriodPercent * blocksFromLastBlock;
                }
            }
        }
        else if (block.number <= thirdRewardPeriodEndBlock) {
            if (blocksFromLastBlock > thirdLoos) {
                if (lastBlock < firstRewardPeriodEndBlock) {
                    rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * (firstRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * secondRewardPeriodPercent * (thirdRewardPeriodEndBlock - secondRewardPeriodEndBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (thirdRewardPeriodEndBlock - block.number);
                }
                else if (lastBlock < secondRewardPeriodEndBlock) {
                    rewardAmount = previousBalanceFrom * secondRewardPeriodPercent * (secondRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (thirdRewardPeriodEndBlock - block.number);
                }
                else {
                    rewardAmount = previousBalanceFrom * thirdRewardPeriodPercent * blocksFromLastBlock;
                }
            }
        }
        else if (block.number <= finalRewardPeriodEndBlock) {
            if (blocksFromLastBlock > finalLoos) {
                if (lastBlock < firstRewardPeriodEndBlock) {
                    rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * (firstRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * secondRewardPeriodPercent * (thirdRewardPeriodEndBlock - secondRewardPeriodEndBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                }
                else if (lastBlock < secondRewardPeriodEndBlock) {
                    rewardAmount = previousBalanceFrom * secondRewardPeriodPercent * (secondRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                }
                else if (lastBlock < secondRewardPeriodEndBlock) {
                    rewardAmount = previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                }
                else {
                    rewardAmount = previousBalanceFrom * finalRewardPeriodPercent * blocksFromLastBlock;
                }
            }
        }
        else {
            if (blocksFromLastBlock > finalLoos) {
                if (lastBlock < firstRewardPeriodEndBlock) {
                    rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * (firstRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * secondRewardPeriodPercent * (thirdRewardPeriodEndBlock - secondRewardPeriodEndBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                }
                else if (lastBlock < secondRewardPeriodEndBlock) {
                    rewardAmount = previousBalanceFrom * secondRewardPeriodPercent * (secondRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                }
                else if (lastBlock < secondRewardPeriodEndBlock) {
                    rewardAmount = previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                }
                else {
                    rewardAmount = previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock);
                }
            }
        }

        rewardAmount = rewardAmount / 10000;
        uint curTotalSupply = 0;

        updateValueAtNow(balances[_from], previousBalanceFrom - _amount + rewardAmount);

        // UPDATE TOTAL
        if (rewardAmount > 0) {
            curTotalSupply = getValueAt(totalSupplyHistory, block.number);
            if (curTotalSupply + rewardAmount < curTotalSupply) throw; // Check for overflow
            updateValueAtNow(totalSupplyHistory, curTotalSupply + rewardAmount);
        }

        rewardAmount = 0;

        var previousBalanceTo = balanceOfAt(_to, block.number);
        if (previousBalanceTo + _amount < previousBalanceTo) throw;

        checkpoints = balances[_to];
        if (checkpoints.length > 0) {
            lastBlock = checkpoints[checkpoints.length - 1].fromBlock;
            blocksFromLastBlock = block.number - lastBlock;

            if (_amount >= (previousBalanceTo / 3)) {
                if (blocksFromLastBlock > finalLoos) {

                    if (block.number <= firstRewardPeriodEndBlock) {
                        rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * blocksFromLastBlock;
                    }
                    else if (block.number <= secondRewardPeriodEndBlock) {

                        if (lastBlock < firstRewardPeriodEndBlock) {
                            rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * (firstRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * secondRewardPeriodPercent * (secondRewardPeriodEndBlock - block.number);
                        }
                        else {
                            rewardAmount = previousBalanceFrom * secondRewardPeriodPercent * blocksFromLastBlock;
                        }

                    }
                    else if (block.number <= thirdRewardPeriodEndBlock) {

                        if (lastBlock < firstRewardPeriodEndBlock) {
                            rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * (firstRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * secondRewardPeriodPercent * (thirdRewardPeriodEndBlock - secondRewardPeriodEndBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (thirdRewardPeriodEndBlock - block.number);
                        }
                        else if (lastBlock < secondRewardPeriodEndBlock) {
                            rewardAmount = previousBalanceFrom * secondRewardPeriodPercent * (secondRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (thirdRewardPeriodEndBlock - block.number);
                        }
                        else {
                            rewardAmount = previousBalanceFrom * thirdRewardPeriodPercent * blocksFromLastBlock;
                        }

                    }
                    else if (block.number <= finalRewardPeriodEndBlock) {

                        if (lastBlock < firstRewardPeriodEndBlock) {
                            rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * (firstRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * secondRewardPeriodPercent * (thirdRewardPeriodEndBlock - secondRewardPeriodEndBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                        }
                        else if (lastBlock < secondRewardPeriodEndBlock) {
                            rewardAmount = previousBalanceFrom * secondRewardPeriodPercent * (secondRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                        }
                        else if (lastBlock < secondRewardPeriodEndBlock) {
                            rewardAmount = previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                        }
                        else {
                            rewardAmount = previousBalanceFrom * finalRewardPeriodPercent * blocksFromLastBlock;
                        }

                    }
                    else {

                        if (lastBlock < firstRewardPeriodEndBlock) {
                            rewardAmount = previousBalanceFrom * firstRewardPeriodPercent * (firstRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * secondRewardPeriodPercent * (thirdRewardPeriodEndBlock - secondRewardPeriodEndBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                        }
                        else if (lastBlock < secondRewardPeriodEndBlock) {
                            rewardAmount = previousBalanceFrom * secondRewardPeriodPercent * (secondRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                        }
                        else if (lastBlock < secondRewardPeriodEndBlock) {
                            rewardAmount = previousBalanceFrom * thirdRewardPeriodPercent * (finalRewardPeriodEndBlock - lastBlock) + previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - block.number);
                        }
                        else {
                            rewardAmount = previousBalanceFrom * finalRewardPeriodPercent * (finalRewardPeriodEndBlock - thirdRewardPeriodEndBlock);
                        }
                    }

                }
            }

        }

        rewardAmount = rewardAmount / 10000;
        updateValueAtNow(balances[_to], previousBalanceTo + _amount + rewardAmount);

        // UPDATE TOTAL
        if (rewardAmount > 0) {
            curTotalSupply = getValueAt(totalSupplyHistory, block.number);
            if (curTotalSupply + rewardAmount < curTotalSupply) throw;
            // Check for overflow
            updateValueAtNow(totalSupplyHistory, curTotalSupply + rewardAmount);
        }

        Transfer(_from, _to, _amount);

        return true;
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balanceOfAt(_owner, block.number);
    }

    function approve(address _spender, uint256 _amount) returns (bool success) {
        if (!transfersEnabled) throw;

        if ((_amount != 0) && (allowed[msg.sender][_spender] != 0)) throw;

        if (isContract(controller)) {
            if (!TokenController(controller).onApprove(msg.sender, _spender, _amount))
            throw;
        }

        allowed[msg.sender][_spender] = _amount;
        Approval(msg.sender, _spender, _amount);
        return true;
    }

    function allowance(address _owner, address _spender
    ) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function approveAndCall(address _spender, uint256 _amount, bytes _extraData
    ) returns (bool success) {
        if (!approve(_spender, _amount)) throw;

        ApproveAndCallFallBack(_spender).receiveApproval(
        msg.sender,
        _amount,
        this,
        _extraData
        );

        return true;
    }

    function totalSupply() constant returns (uint) {
        return totalSupplyAt(block.number);
    }

    function getBalancesOfAddress(address _owner) onlyController returns (uint128, uint128) {
        Checkpoint[] checkpoints = balances[_owner];
        return (checkpoints[checkpoints.length - 1].value, checkpoints[checkpoints.length - 1].fromBlock);
    }

    function balanceOfAt(address _owner, uint _blockNumber) constant
    returns (uint) {

        if ((balances[_owner].length == 0)
        || (balances[_owner][0].fromBlock > _blockNumber)) {
            if (address(parentToken) != 0) {
                return parentToken.balanceOfAt(_owner, min(_blockNumber, parentSnapShotBlock));
            }
            else {
                return 0;
            }
        }
        else {
            return getValueAt(balances[_owner], _blockNumber);
        }
    }

    function totalSupplyAt(uint _blockNumber) constant returns (uint) {
        if ((totalSupplyHistory.length == 0)
        || (totalSupplyHistory[0].fromBlock > _blockNumber)) {
            if (address(parentToken) != 0) {
                return parentToken.totalSupplyAt(min(_blockNumber, parentSnapShotBlock));
            }
            else {
                return 0;
            }
        }
        else {
            return getValueAt(totalSupplyHistory, _blockNumber);
        }
    }


    function createCloneToken(
        string _cloneTokenName,
        uint8 _cloneDecimalUnits,
        string _cloneTokenSymbol,
        uint _snapshotBlock,
        bool _transfersEnabled
    ) returns (address) {
        if (_snapshotBlock == 0) _snapshotBlock = block.number;
        ShineCoinToken cloneToken = tokenFactory.createCloneToken(
        this,
        _snapshotBlock,
        _cloneTokenName,
        _cloneDecimalUnits,
        _cloneTokenSymbol,
        _transfersEnabled
        );

        cloneToken.changeController(msg.sender);

        NewCloneToken(address(cloneToken), _snapshotBlock);
        return address(cloneToken);
    }

    function generateTokens(address _owner, uint _amount
    ) onlyController returns (bool) {
        uint curTotalSupply = getValueAt(totalSupplyHistory, block.number);
        if (curTotalSupply + _amount < curTotalSupply) throw;

        updateValueAtNow(totalSupplyHistory, curTotalSupply + _amount);
        var previousBalanceTo = balanceOf(_owner);
        if (previousBalanceTo + _amount < previousBalanceTo) throw;

        updateValueAtNow(balances[_owner], previousBalanceTo + _amount);
        Transfer(0, _owner, _amount);
        return true;
    }

    function destroyTokens(address _owner, uint _amount
    ) onlyController returns (bool) {
        uint curTotalSupply = getValueAt(totalSupplyHistory, block.number);
        if (curTotalSupply < _amount) throw;
        updateValueAtNow(totalSupplyHistory, curTotalSupply - _amount);
        var previousBalanceFrom = balanceOf(_owner);
        if (previousBalanceFrom < _amount) throw;
        updateValueAtNow(balances[_owner], previousBalanceFrom - _amount);
        Transfer(_owner, 0, _amount);
        return true;
    }

    function enableTransfers(bool _transfersEnabled) onlyController {
        transfersEnabled = _transfersEnabled;
    }

    function getValueAt(Checkpoint[] storage checkpoints, uint _block
    ) constant internal returns (uint) {
        if (checkpoints.length == 0) return 0;

        if (_block >= checkpoints[checkpoints.length - 1].fromBlock)
        return checkpoints[checkpoints.length - 1].value;
        if (_block < checkpoints[0].fromBlock) return 0;

        uint min = 0;
        uint max = checkpoints.length - 1;
        while (max > min) {
            uint mid = (max + min + 1) / 2;
            if (checkpoints[mid].fromBlock <= _block) {
                min = mid;
            }
            else {
                max = mid - 1;
            }
        }
        return checkpoints[min].value;
    }

    function updateValueAtNow(Checkpoint[] storage checkpoints, uint _value
    ) internal {
        if ((checkpoints.length == 0)
        || (checkpoints[checkpoints.length - 1].fromBlock < block.number)) {
            Checkpoint newCheckPoint = checkpoints[checkpoints.length++];
            newCheckPoint.fromBlock = uint128(block.number);
            newCheckPoint.value = uint128(_value);
        }
        else {
            Checkpoint oldCheckPoint = checkpoints[checkpoints.length - 1];
            oldCheckPoint.value = uint128(_value);
        }
    }

    function isContract(address _addr) constant internal returns (bool) {
        uint size;
        if (_addr == 0) return false;
        assembly {
        size := extcodesize(_addr)
        }
        return size > 0;
    }

    function min(uint a, uint b) internal returns (uint) {
        return a < b ? a : b;
    }

    function() payable {
        if (isContract(controller)) {
            if (!TokenController(controller).proxyPayment.value(msg.value)(msg.sender))
            throw;
        }
        else {
            throw;
        }
    }

    event Transfer(address indexed _from, address indexed _to, uint256 _amount);

    event NewCloneToken(address indexed _cloneToken, uint _snapshotBlock);

    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _amount
    );

}

contract ShineCoinTokenFactory {
        function createCloneToken(
        address _parentToken,
        uint _snapshotBlock,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        bool _transfersEnabled
    ) returns (ShineCoinToken) {
        ShineCoinToken newToken = new ShineCoinToken(
        this,
        _parentToken,
        _snapshotBlock,
        _tokenName,
        _decimalUnits,
        _tokenSymbol,
        _transfersEnabled
        );
        newToken.changeController(msg.sender);
        return newToken;
    }
}