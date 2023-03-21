/*
Copyright © 2023 bokunodev bokunocode@gmail.com
*/
package cmd

import (
	"encoding/hex"
	"fmt"
	"math/rand"

	"github.com/spf13/cobra"

	"github.com/bokunodev/uid"
)

var parseCmd = &cobra.Command{
	Use:   "parse",
	Short: "parse string and return information about the uid",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		epoch, err := cmd.Flags().GetInt64("epoch")
		cobra.CheckErr(err)
		sequence, err := cmd.Flags().GetUint32("sequence")
		cobra.CheckErr(err)

		gen := uid.New(epoch, sequence)
		id, err := uid.Parse(args[0])
		cobra.CheckErr(err)

		ts, seq, ent := gen.Extract(id)
		fmt.Println(ts, seq, hex.EncodeToString(ent[:]))
	},
}

func init() {
	flags := parseCmd.Flags()
	flags.Int64("epoch", uid.SnowflakeEpoch, "unix timestamp custom epoch in seconds")
	flags.Uint32("sequence", rand.Uint32(), "sequence starting point")

	rootCmd.AddCommand(parseCmd)
}
