// SPDX-License-Identifier: NONE
pragma solidity ^0.8.4;

import "./access/Ownable.sol";
import "./interfaces/IBEP20.sol";

contract ExampleToken is IBEP20, Ownable {
    uint256   public override totalSupply;
    uint8     public override decimals = 18;
    string    public override symbol;
    string    public override name;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    function getOwner() external override view returns (address) { return owner(); }

    function balanceOf(address _account) external override view returns (uint256) {
        return _balances[_account];
    }

    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external override view returns (uint256) {
        return _allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external override returns (bool) {
        require(_allowances[_sender][msg.sender] >= _amount, 'BEP20: Insufficient allowance for transfer');
        _transfer(_sender, _recipient, _amount);
        _approve(_sender, msg.sender, _allowances[_sender][msg.sender] - _amount);
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) public returns (bool) {
        _approve(msg.sender, _spender, _allowances[msg.sender][_spender] + _addedValue);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
        _approve(msg.sender, _spender, _allowances[msg.sender][_spender] - _subtractedValue);
        return true;
    }

    function mint(uint256 _amount) public onlyOwner returns (bool) {
        _mint(msg.sender, _amount);
        return true;
    }

    function mintTo(address _to, uint256 _amount) public onlyOwner returns (bool) {
        _mint(_to, _amount);
        return true;
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "BEP20: Cannot transfer from the zero address");
        require(_recipient != address(0), "BEP20: Cannot transfer to the zero address");

        _balances[_sender] = _balances[_sender] - _amount;
        _balances[_recipient] = _balances[_recipient] + _amount;
        emit Transfer(_sender, _recipient, _amount);
    }

    function _mint(address _account, uint256 _amount) private {
        require(_account != address(0), "BEP20: Cannot mint to the zero address");

        totalSupply = totalSupply + _amount;
        _balances[_account] = _balances[_account] + _amount;
        emit Transfer(address(0), _account, _amount);
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "BEP20: Cannot approve from the zero address");
        require(_spender != address(0), "BEP20: Cannot approve to the zero address");

        _allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }
}