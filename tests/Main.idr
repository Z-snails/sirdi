module Main

import Test.Golden

allTests : TestPool
allTests = MkTestPool "Sirdi golden tests" [] Nothing
    [ "new-project-can-be-built"
    ]

main : IO ()
main = runner
    [ testPaths "sirdi" allTests ]
    where
      testPaths : String -> TestPool -> TestPool
      testPaths dir = record { testCases $= map ((dir ++ "/" ++)) }

