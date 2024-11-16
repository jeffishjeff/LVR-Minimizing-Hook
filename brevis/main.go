package main

import (
	"context"
	"fmt"
	"log"
	"math/big"

	"brevis-variance-app/circuits"
	"brevis-variance-app/config"

	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/brevis-network/brevis-sdk/sdk/proto/gwproto"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

func main() {

	cfg, err := config.ConfigFromEnv()
	if err != nil {
		log.Fatal(err)
	}

	eth, err := ethclient.Dial(cfg.RPC)
	if err != nil {
		log.Fatal(err)
	}

	blockNum, err := eth.BlockNumber(context.Background())
	if err != nil {
		log.Fatal(err)
	}

	app, err := sdk.NewBrevisApp(cfg.SrcChainID, cfg.RPC, cfg.OutDir)
	if err != nil {
		log.Fatal(err)
	}

	slot8 := common.LeftPadBytes([]byte{8}, 32)
	// add last 30 days slot
	for i := 0; i < 30; i++ {
		app.AddStorage(sdk.StorageData{
			BlockNum: big.NewInt(int64(blockNum - uint64(i*7200))),
			Address:  cfg.PoolAddress,
			Slot:     common.BytesToHash(slot8),
		})
	}

	appCircuit := &circuits.AppCircuit{}

	compiledCircuit, pk, vk, _, err := sdk.ReadSetupFrom(appCircuit, cfg.OutDir)
	if err != nil {
		compiledCircuit, pk, vk, _, err = sdk.Compile(appCircuit, cfg.OutDir, cfg.SRSDir)
		if err != nil {
			log.Fatal(err)
		}
	}

	fmt.Println(pk, vk)

	input, err := app.BuildCircuitInput(appCircuit)
	if err != nil {
		log.Fatal(err)
	}

	witness, _, err := sdk.NewFullWitness(appCircuit, input)
	proof, err := sdk.Prove(compiledCircuit, pk, witness)

	calldata, requestID, nonce, feevalue, err := app.PrepareRequest(
		vk, witness, cfg.DstChainID, cfg.DstChainID, cfg.Refundee, cfg.AppContract, 0, gwproto.QueryOption_ZK_MODE.Enum(), "",
	)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println("##########################################")
	fmt.Printf("Calldata:  %s\n", common.Bytes2Hex(calldata))
	fmt.Printf("RequestID: %s\n", requestID.String())
	fmt.Printf("Nonce:     %d\n", nonce)
	fmt.Printf("Gas Fee:   %s\n", feevalue.String())
	fmt.Println("##########################################")
	// TODO: pay gas fee with requestID?

	err = app.SubmitProof(proof)
	if err != nil {
		log.Fatal(err)
	}

}
