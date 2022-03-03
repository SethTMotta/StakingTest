const { assert } = require('chai');
const { time } = require('@openzeppelin/test-helpers');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');

const StakingPool = artifacts.require('StakingPool');
const ExampleToken = artifacts.require('ExampleToken');

const Address = artifacts.require('Address');
const SafeMath = artifacts.require('SafeMath');
const SafeBEP20 = artifacts.require('SafeBEP20');

const WINGNUT = '0xF7684b0d168B77096Ffb6b4cab74ac6fA4ae6748';
const STAKE_TIME = 604800;

function tokens(n) {
    return web3.utils.toWei(n, 'Ether');
}

contract('StakingPool', ([ deployer ]) => {
    let address, safemath, safebep20;
    let pool, stake, reward;
    let block;
    let BN = web3.utils.BN;
    let transactionCount = 0;

    async function nonce() {
        transactionCount += 1;
        return await web3.eth.getTransactionCount(await deployer, 'pending') + (transactionCount - 1);
    }

    before(async() => {
        address = await Address.new({ nonce: await nonce() });
        safemath = await SafeMath.new({ nonce: await nonce() });        
    });

    describe('Test Environment Setup', async() => {
        it('1. Deploy library contracts', async() => {
            address = await Address.new({ nonce: await nonce() });
            safemath = await SafeMath.new({ nonce: await nonce() });
            await SafeBEP20.link(address);
            await SafeBEP20.link(safemath);
            safebep20 = await SafeBEP20.new({ nonce: await nonce() })
            await StakingPool.link(safebep20);
        });
        it('2. Deploy staking pool and tokens', async() => {
            stake = await ExampleToken.new('Stake Test 1', 'stake', { nonce: await nonce() });
            await stake.mint(tokens('1000'), { nonce: await nonce() });
            reward = await ExampleToken.new('Reward Test 1', 'reward', { nonce: await nonce() });
            await reward.mint(tokens('1000000'), { nonce: await nonce() });
            pool = await StakingPool.new(stake.address, reward.address, WINGNUT, STAKE_TIME, { nonce: await nonce() });
            await reward.transfer(pool.address, tokens('1000000'), { nonce: await nonce() });
            let stakeTokenBalance = await stake.balanceOf(deployer);
            stakeTokenBalance = new BN(stakeTokenBalance.toString());
            assert.isTrue(stakeTokenBalance.eq(new BN(tokens('1000'))), 'Deployer does not have the staking tokens');
            let rewardTokenBalance = await reward.balanceOf(pool.address);
            rewardTokenBalance = new BN(rewardTokenBalance.toString());
            assert.isTrue(rewardTokenBalance.eq(new BN(tokens('1000000'))), 'Staking contract does not have the reward tokens');
        });
    });

    describe('Contract Functionality Tests', async() => {
        it('1. Initialize the contract to start rewards in 10 blocks', async() => {
            block = parseInt(await time.latestBlock());
            await pool.initialize(tokens('2'), block + 10, block + 500010, { nonce: await nonce() });
        });
        it('2. Deployer can stake 100 tokens in the pool', async() => {
            await stake.approve(pool.address, tokens('100'), { nonce: await nonce() });
            await pool.deposit(tokens('100'), { nonce: await nonce() });
            let tokenBalance = await stake.balanceOf(deployer);
            assert.equal(tokenBalance.toString(), tokens('900').toString(), 'Deployer does not have the correct amount of staking tokens');
            let poolBalance = await stake.balanceOf(pool.address);
            assert.equal(poolBalance.toString(), tokens('100').toString(), 'Staking contract does not have the correct amount of staking tokens');
            let stakedAmount = await pool.userInfo(deployer);
            assert.equal(stakedAmount.amount.toString(), tokens('100').toString(), 'Deployer does not have the correct amount of staked tokens');
        });
        it('3. Advance to 10 blocks past the start block and confirm pending rewards', async() => {
            let target = block + 20;
            while (block < target) {
                await time.advanceBlock();
                block = await time.latestBlock();
            }
            let pending = await pool.pendingReward(deployer);
            assert.equal(pending.toString(), tokens('20').toString(), 'Pending rewards balance is not correct');
        });
        it('4. Cannot standard withdraw as not passed the minimum stake time', async() => {
            try {
                await pool.withdraw(tokens('100'), { nonce: await nonce() });
            } catch (error) {
                assert(error.message.includes('Staking: Token is still locked, use #withdrawEarly to withdraw funds before the end of your staking period.'));                
                return;
            }
            assert(false)
        });
        it('5. Cannot early withdraw more than staked', async() => {
            try {
                await pool.withdrawEarly(tokens('101'), { nonce: await nonce() });
            } catch (error) {
                assert(error.message.includes('Amount to withdraw too high'));                
                return;
            }
            assert(false)
        });
        it('6. Can do an early withdraw with rewards going to the treasury', async() => {
            let pending = await pool.pendingReward(deployer);
            // Add one block of rewards to the amount
            pending = new BN(pending).add(new BN(tokens('2'))).toString();
            await pool.withdrawEarly(tokens('100'), { nonce: await nonce() });
            let tokenBalance = await stake.balanceOf(deployer);
            assert.equal(tokenBalance.toString(), tokens('1000').toString(), 'Deployer does not have the correct balance of staking tokens');
            let rewards = await reward.balanceOf(WINGNUT);
            assert.equal(pending.toString(), rewards.toString(), 'Treasury did not receive the forfeited rewards');
        });
        it('7. Deployer can stake 100 tokens in the pool again', async() => {
            await stake.approve(pool.address, tokens('100'), { nonce: await nonce() });
            await pool.deposit(tokens('100'), { nonce: await nonce() });
            block = parseInt(await time.latestBlock());
            let tokenBalance = await stake.balanceOf(deployer);
            assert.equal(tokenBalance.toString(), tokens('900').toString(), 'Deployer does not have the correct amount of staking tokens');
            let poolBalance = await stake.balanceOf(pool.address);
            assert.equal(poolBalance.toString(), tokens('100').toString(), 'Staking contract does not have the correct amount of staking tokens');
            let stakedAmount = await pool.userInfo(deployer);
            assert.equal(stakedAmount.amount.toString(), tokens('100').toString(), 'Deployer does not have the correct amount of staked tokens');
        });
        it('8. Advance to 10 blocks past the staked block and confirm pending rewards', async() => {
            let target = block + 10;
            while (block < target) {
                await time.advanceBlock();
                block = await time.latestBlock();
            }
            let pending = await pool.pendingReward(deployer);
            assert.equal(pending.toString(), tokens('20').toString(), 'Pending rewards balance is not correct');
        });
        it('9. Deployer can do an emergency withdraw and get tokens back', async() => {
            await pool.emergencyWithdraw({ nonce: await nonce() });
            let tokenBalance = await stake.balanceOf(deployer);
            assert.equal(tokenBalance.toString(), tokens('1000').toString(), 'Deployer does not have the correct amount of staking tokens');
        });
        it('10. Deployer can stake 100 tokens in the pool again', async() => {
            await stake.approve(pool.address, tokens('100'), { nonce: await nonce() });
            await pool.deposit(tokens('100'), { nonce: await nonce() });
            block = parseInt(await time.latestBlock());
            let tokenBalance = await stake.balanceOf(deployer);
            assert.equal(tokenBalance.toString(), tokens('900').toString(), 'Deployer does not have the correct amount of staking tokens');
            let poolBalance = await stake.balanceOf(pool.address);
            assert.equal(poolBalance.toString(), tokens('100').toString(), 'Staking contract does not have the correct amount of staking tokens');
            let stakedAmount = await pool.userInfo(deployer);
            assert.equal(stakedAmount.amount.toString(), tokens('100').toString(), 'Deployer does not have the correct amount of staked tokens');
        });
        it('11. Advance to 10 blocks past the staked block and confirm pending rewards', async() => {
            let target = block + 10;
            while (block < target) {
                await time.advanceBlock();
                block = await time.latestBlock();
            }
            let pending = await pool.pendingReward(deployer);
            assert.equal(pending.toString(), tokens('20').toString(), 'Pending rewards balance is not correct');
        });
        it('12. Can do an withdraw of 0 tokens and receive rewards', async() => {
            let pending = await pool.pendingReward(deployer);
            // Add one block of rewards to the amount
            pending = new BN(pending).add(new BN(tokens('2'))).toString();
            await pool.withdraw(0, { nonce: await nonce() });
            let tokenBalance = await stake.balanceOf(deployer);
            assert.equal(tokenBalance.toString(), tokens('900').toString(), 'Deployer does not have the correct balance of staking tokens');
            let rewards = await reward.balanceOf(deployer);
            assert.equal(pending.toString(), rewards.toString(), 'Deployer did not receive the rewards');
        });
        it('15. Time should move 7 days forward', async() => {
            const timeThen = await time.latest();
            const ahead = STAKE_TIME + 1000;
            await time.increase(ahead);
            const timeNow = await time.latest();
            const diff = timeNow - timeThen;
            assert.isTrue(diff >= ahead);
        });
        it('16. Can do an withdraw of all tokens and receive rewards', async() => {
            let pending = await pool.pendingReward(deployer);
            // Add one block of rewards to the amount
            pending = new BN(pending).add(new BN(tokens('2'))).toString();
            let rewardsBalance = await reward.balanceOf(deployer);
            await pool.withdraw(tokens('100'), { nonce: await nonce() });
            let tokenBalance = await stake.balanceOf(deployer);
            assert.equal(tokenBalance.toString(), tokens('1000').toString(), 'Deployer does not have the correct balance of staking tokens');
            let rewards = await reward.balanceOf(deployer);
            // Add the previous balance to the pending amount for comparison
            pending = new BN(pending).add(new BN(rewardsBalance)).toString();
            assert.equal(pending.toString(), rewards.toString(), 'Deployer did not receive the rewards');
        });
    });
});