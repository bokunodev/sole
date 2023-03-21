/*
Copyright © 2023 bokunodev bokunocode@gmail.com
*/
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/bokunodev/uid"
)

var genCmd = &cobra.Command{
	Use:   "gen",
	Short: "generate uid",
	Run: func(cmd *cobra.Command, _ []string) {
		n, err := cmd.Flags().GetUint("count")
		cobra.CheckErr(err)
		epoch, err := cmd.Flags().GetInt64("epoch")
		cobra.CheckErr(err)
		sequence, err := cmd.Flags().GetUint32("sequence")
		cobra.CheckErr(err)

		gen := uid.New(epoch, sequence)

		for i := 0; i < int(n); i++ {
			fmt.Println(gen.NewID())
		}
	},
}

func init() {
	flags := genCmd.Flags()
	flags.UintP("count", "n", 1, "configure to generate (count) ammount of uids")
	flags.Int64("epoch", uid.SnowflakeEpoch, "unix timestamp custom epoch in seconds")
	flags.Uint32("sequence", 0, "sequence starting point")

	rootCmd.AddCommand(genCmd)
}
