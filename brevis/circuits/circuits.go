package circuits

import (
	"fmt"
	"github.com/brevis-network/brevis-sdk/sdk"
)

type AppCircuit struct {}

func (c *AppCircuit) Allocate() (maxReceipts, maxSlots, maxTransactions int) {
	return 0, 32, 0
}

func (c *AppCircuit) Define(api *sdk.CircuitAPI, in sdk.DataInput) error {
	u248 := api.Uint248
	// u32 := api.Uint32
	slots := sdk.NewDataStream(api, in.StorageSlots)

	// filtered := sdk.Filter(slots, func(cur sdk.StorageSlot) sdk.Uint248 { return u248.Not(u248.IsZero(sdk.Uint248(cur.BlockNum))) })

	prices := sdk.Map(slots, func(cur sdk.StorageSlot) sdk.Uint248 {
		return decodePrice(api, cur.Value)
	})

	count := sdk.Count(prices)
	average, _ := u248.Div(sdk.Sum(prices), count)

	variances := sdk.Map(prices, func(cur sdk.Uint248) sdk.Uint248 {
		return u248.Select(
			u248.IsGreaterThan(cur, average),
			u248.Mul(u248.Sub(cur, average), u248.Sub(cur, average)),
			u248.Mul(u248.Sub(average, cur), u248.Sub(average, cur)),
		)
	})

	variance, _ := u248.Div(sdk.Sum(variances), count)

	fmt.Println(variance)

	api.OutputUint(248, variance)
	return nil
}

func decodePrice(api *sdk.CircuitAPI, data sdk.Bytes32) sdk.Uint248 {
	bits := api.Bytes32.ToBinary(data)
	reserve1 := api.Bytes32.FromBinary(bits[32:144]...)
	reserve0 := api.Bytes32.FromBinary(bits[144:]...)
	// fmt.Println(api.ToUint248(reserve1), api.ToUint248(reserve0))
	price, _ := api.Uint248.Div(api.ToUint248(reserve1), api.ToUint248(reserve0))
	return price
}

