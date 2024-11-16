package circuits

import (
	"fmt"
	"math/big"
	"testing"

	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/brevis-network/brevis-sdk/test"
	"github.com/ethereum/go-ethereum/common"

	"brevis-variance-app/config"
)

func TestE2E(t *testing.T) {
	cfg, _ := config.ConfigFromEnv()
	app, err := sdk.NewBrevisApp(cfg.SrcChainID, cfg.RPC, cfg.OutDir)
	check(err)

	var slot8 = common.LeftPadBytes([]byte{8}, 32)

	app.AddStorage(sdk.StorageData{
		BlockNum: big.NewInt(21201210),
		Address:  cfg.PoolAddress,
		Slot:     common.BytesToHash(slot8),
	})

	app.AddStorage(sdk.StorageData{
		BlockNum: big.NewInt(21195450),
		Address:  cfg.PoolAddress,
		Slot:     common.BytesToHash(slot8),
	})

	appCircuit := &AppCircuit{}
	appCircuitAssignment := &AppCircuit{}

	in, err := app.BuildCircuitInput(appCircuit)
	check(err)

	test.ProverSucceeded(t, appCircuit, appCircuitAssignment, in)

	compiledCircuit, pk, vk, _, err := sdk.Compile(appCircuit, cfg.OutDir, cfg.SRSDir)
	check(err)

	compiledCircuit, pk, vk, _, err = sdk.ReadSetupFrom(appCircuit, cfg.OutDir)
	check(err)

	fmt.Println(">> prove")
	witness, publicWitness, err := sdk.NewFullWitness(appCircuitAssignment, in)
	check(err)
	proof, err := sdk.Prove(compiledCircuit, pk, witness)
	check(err)

	err = sdk.Verify(vk, publicWitness, proof)
	check(err)
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}
