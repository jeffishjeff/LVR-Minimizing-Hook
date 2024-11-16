package config

import (
	"errors"
	"os"
	"strconv"

	"github.com/ethereum/go-ethereum/common"
)

type Config struct {
	RPC        string
	SrcChainID uint64
	DstChainID uint64
	OutDir     string
	SRSDir     string

	PoolAddress common.Address
	Refundee    common.Address
	AppContract common.Address
}

func ConfigFromEnv() (cfg Config, err error) {

	if cfg.RPC = os.Getenv("RPC_URL"); cfg.RPC == "" {
		err = errors.New("empty rpc url")
		return
	}

	cfg.SrcChainID, err = strconv.ParseUint(os.Getenv("SRC_CHAIN_ID"), 10, 64)
	if err != nil {
		err = errors.New("wrong source chain id")
		return
	}

	cfg.DstChainID, err = strconv.ParseUint(os.Getenv("DST_CHAIN_ID"), 10, 64)
	if err != nil {
		err = errors.New("wrong source chain id")
		return
	}

	if cfg.OutDir = os.Getenv("BREVIS_OUT_DIR"); cfg.OutDir == "" {
		err = errors.New("empty out dir")
		return
	}

	if cfg.SRSDir = os.Getenv("BREVIS_SRS_DIR"); cfg.SRSDir == "" {
		err = errors.New("empty srs dir")
		return
	}

	poolAddress := os.Getenv("POOL_ADDRESS")
	if poolAddress == "" {
		err = errors.New("empty pool address")
		return
	}
	cfg.PoolAddress = common.HexToAddress(poolAddress)

	refundee := os.Getenv("BREVIS_REFUNDEE")
	if refundee == "" {
		err = errors.New("empty refundee")
		return
	}
	cfg.Refundee = common.HexToAddress(refundee)

	appContract := os.Getenv("APP_CONTRACT")
	cfg.AppContract = common.HexToAddress(appContract)

	return
}
