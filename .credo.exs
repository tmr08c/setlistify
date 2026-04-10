%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "src/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/web/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: [],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: [
        #
        # Checks handled by Styler — disabled to avoid overlap.
        # See: https://hexdocs.pm/styler/credo.html
        #
        {Credo.Check.Consistency.MultiAliasImportRequireUse, false},
        {Credo.Check.Consistency.ParameterPatternMatching, false},
        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Readability.AliasOrder, false},
        {Credo.Check.Readability.BlockPipe, false},
        {Credo.Check.Readability.LargeNumbers, false},
        {Credo.Check.Readability.ModuleDoc, false},
        {Credo.Check.Readability.MultiAlias, false},
        {Credo.Check.Readability.OneArityFunctionInPipe, false},
        {Credo.Check.Readability.ParenthesesOnZeroArityDefs, false},
        {Credo.Check.Readability.PipeIntoAnonymousFunctions, false},
        {Credo.Check.Readability.PreferImplicitTry, false},
        {Credo.Check.Readability.SinglePipe, false},
        {Credo.Check.Readability.StrictModuleLayout, false},
        {Credo.Check.Readability.StringSigils, false},
        {Credo.Check.Readability.UnnecessaryAliasExpansion, false},
        {Credo.Check.Readability.WithSingleClause, false},
        {Credo.Check.Refactor.CaseTrivialMatches, false},
        {Credo.Check.Refactor.CondStatements, false},
        {Credo.Check.Refactor.FilterCount, false},
        {Credo.Check.Refactor.MapInto, false},
        {Credo.Check.Refactor.MapJoin, false},
        {Credo.Check.Refactor.NegatedConditionsInUnless, false},
        {Credo.Check.Refactor.NegatedConditionsWithElse, false},
        {Credo.Check.Refactor.PipeChainStart, false},
        {Credo.Check.Refactor.RedundantWithClauseResult, false},
        {Credo.Check.Refactor.UnlessWithElse, false},
        {Credo.Check.Refactor.WithClauses, false}
      ]
    }
  ]
}
