//SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

//solhint-disable
interface ICurveFactory {
    function metapool_implementations(address _base_pool)
        external
        view
        returns (address[10] memory);

    function find_pool_for_coins(address _from, address _to) external view returns (address);

    function find_pool_for_coins(
        address _from,
        address _to,
        uint256 i
    ) external view returns (address);

    function get_base_pool(address _pool) external view returns (address);

    function get_n_coins(address _pool) external view returns (uint256);

    function get_meta_n_coins(address _pool) external view returns (uint256, uint256);

    function get_coins(address _pool) external view returns (address[4] memory);

    function get_underlying_coins(address _pool) external view returns (address[8] memory);

    function get_decimals(address _pool) external view returns (uint256[4] memory);

    function get_underlying_decimals(address _pool) external view returns (uint256[8] memory);

    function get_metapool_rates(address _pool) external view returns (uint256[2] memory);

    function get_balances(address _pool) external view returns (uint256[4] memory);

    function get_underlying_balances(address _pool) external view returns (uint256[8] memory);

    function get_A(address _pool) external view returns (uint256);

    function get_fees(address _pool) external view returns (uint256, uint256);

    function get_admin_balances(address _pool) external view returns (uint256[4] memory);

    function get_coin_indices(
        address _pool,
        address _from,
        address _to
    )
        external
        view
        returns (
            int128,
            int128,
            bool
        );

    function get_gauge(address _pool) external view returns (address);

    function get_implementation_address(address _pool) external view returns (address);

    function is_meta(address _pool) external view returns (bool);

    function get_pool_asset_type(address _pool) external view returns (uint256);

    function get_fee_receiver(address _pool) external view returns (address);

    function deploy_plain_pool(
        string calldata _name,
        string calldata _symbol,
        address[4] calldata _coins,
        uint256 _A,
        uint256 _fee
    ) external returns (address);

    function deploy_plain_pool(
        string calldata _name,
        string calldata _symbol,
        address[4] calldata _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _asset_type
    ) external returns (address);

    function deploy_plain_pool(
        string calldata _name,
        string calldata _symbol,
        address[4] calldata _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _asset_type,
        uint256 _implementation_idx
    ) external returns (address);

    function deploy_metapool(
        address _base_pool,
        string calldata _name,
        string calldata _symbol,
        address _coin,
        uint256 _A,
        uint256 _fee
    ) external returns (address);

    function deploy_metapool(
        address _base_pool,
        string calldata _name,
        string calldata _symbol,
        address _coin,
        uint256 _A,
        uint256 _fee,
        uint256 _implementation_idx
    ) external returns (address);

    function deploy_gauge(address _pool) external returns (address);

    function add_base_pool(
        address _base_pool,
        address _fee_receiver,
        uint256 _asset_type,
        address[10] calldata _implementations
    ) external;

    function set_metapool_implementations(address _base_pool, address[10] calldata _implementations)
        external;

    function set_plain_implementations(uint256 _n_coins, address[10] calldata _implementations)
        external;

    function set_gauge_implementation(address _gauge_implementation) external;

    function set_gauge(address _pool, address _gauge) external;

    function batch_set_pool_asset_type(
        address[32] calldata _pools,
        uint256[32] calldata _asset_types
    ) external;

    function commit_transfer_ownership(address _addr) external;

    function accept_transfer_ownership() external;

    function set_manager(address _manager) external;

    function set_fee_receiver(address _base_pool, address _fee_receiver) external;

    function convert_metapool_fees() external returns (bool);

    function admin() external view returns (address);

    function future_admin() external view returns (address);

    function manager() external view returns (address);

    function pool_list(uint256 arg0) external view returns (address);

    function pool_count() external view returns (uint256);

    function base_pool_list(uint256 arg0) external view returns (address);

    function base_pool_count() external view returns (uint256);

    function plain_implementations(uint256 arg0, uint256 arg1) external view returns (address);

    function fee_receiver() external view returns (address);

    function gauge_implementation() external view returns (address);
}
