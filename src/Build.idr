module Build

import Config
import System
import System.Directory
import Ipkg
import Util
import DepTree


fetchTo : Source -> String -> M ()
fetchTo (Git link) dest = mSystem "git clone \{link} \{dest}" "Failed to clone \{link}"
fetchTo (Local source) dest = mSystem "cp -r \{source} \{dest}" "Failed to copy \{source}"


createBuildDirs : M ()
createBuildDirs = do
    ignore $ mIO $ createDir ".build"
    ignore $ mIO $ createDir ".build/sources"  -- Store the raw git clones
    ignore $ mIO $ createDir ".build/deps"     -- Contains the built dependencies


installDep : String -> M ()
installDep name = do
    ignore $ mIO $ createDir ".build/deps/\{name}"
    ignore $ mIO $ system "cp -r .build/sources/\{name}/build/ttc/* .build/deps/\{name}/"


doBuild : String -> String -> M ()
doBuild pkgName name = do
    mIO $ putStrLn "Building \{name}"
    let dir = ".build/sources/\{name}"
    multiConfig <- readConfig dir
    config <- findSubConfig pkgName multiConfig

    let depNames = map (\d => (d.name, depID d)) config.deps

    traverse_ doBuildDep depNames

    let ipkg = MkIpkg {
        name = name,
        depends = map snd depNames,
        modules = config.modules,
        main = config.main,
        exec = "main" <$ config.main,
        passthru = config.passthru
    }

    writeIpkg ipkg "\{dir}/\{name}.ipkg"

    let setpath = "IDRIS2_PACKAGE_PATH=$(realpath ./.build/deps)"
    mSystem "\{setpath} idris2 --build \{dir}/\{name}.ipkg" "Failed to build \{name}"
        where
            doBuildDep : (String, String) -> M ()
            doBuildDep (pkgName, depName) = do
                n <- mIO $ system "[ -d '.build/deps/\{depName}' ]"

                when (n /= 0) (doBuild pkgName depName >> installDep depName)
                


fetchDeps : String -> String -> M ()
fetchDeps pkgName name = do
    multiConfig <- readConfig ".build/sources/\{name}"

    config <- findSubConfig pkgName multiConfig


    traverse_ fetchDep config.deps

    where
        fetchDep : Dependency -> M ()
        fetchDep dep = do
            let depName = depID dep
            n <- mIO $ system "[ -d '.build/sources/\{depName}' ]"
            when (n /= 0) (fetchTo dep.source ".build/sources/\{depName}")

            fetchDeps dep.name depName


buildDepTree : String -> (dir : String) -> (source : Source) -> M DepTree
buildDepTree pkgName dir source = do
    multiConfig <- readConfig dir
    config <- findSubConfig pkgName multiConfig

    subtrees <- traverse (\dep => buildDepTree dep.name ".build/sources/\{depID dep}" dep.source) config.deps
    pure $ Node (MkDep config.pkgName source) subtrees


export
build : M ()
build = do
    createBuildDirs

    ignore $ mIO $ createDir ".build/sources/main"
    ignore $ mIO $ system "cp ./sirdi.json .build/sources/main"
    ignore $ mIO $ system "cp -r ./src .build/sources/main"

    fetchDeps "main" "main"
    doBuild "main" "main"

    -- Since interactive editors are not yet compatible with sirdi, we must copy
    -- the "build/", ".deps" and "ipkg" back to the project root. This is annoying and
    -- can hopefully be removed eventually.
    ignore $ mIO $ system "cp -r .build/sources/main/build ./"
    ignore $ mIO $ system "cp -r .build/sources/main/main.ipkg ./"
    ignore $ mIO $ system "cp -r .build/deps ./depends"


export
depTree : M ()
depTree = do
    build
    tree <- buildDepTree "main" "." (Local "." )
    mIO $ print tree


export
run : M ()
run = do
    -- We read config files a lot. Perhaps we should add a caching system to the
    -- monad so that config files are kept in memory once they've been read once.
    multiConfig <- readConfig "."
    config <- findSubConfig "main" multiConfig

    case config.main of
         Just _ => do
            build
            ignore $ mIO $ system ".build/sources/main/build/exec/main"
         Nothing => mIO $ putStrLn "Cannot run. No 'main' specified in sirdi configuration file."


export
new : String -> M ()
new name = do
    ignore $ mIO $ createDir "\{name}"
    ignore $ mIO $ createDir "\{name}/src"

    ignore $ mIO $ writeFile "\{name}/sirdi.json" jsonFile
    ignore $ mIO $ writeFile "\{name}/src/Main.idr" idrFile
        where
            idrFile : String
            idrFile = """
            module Main

            main : IO ()
            main = putStrLn "Hello from Idris2!"
            """

            jsonFile : String
            jsonFile = """
            { "deps": [ ], "modules": [ "Main" ], "main": "Main" }

            """

export
clean : M ()
clean = do
    config <- readConfig "."

    ignore $ mIO $ system "rm -rf ./depends"
    ignore $ mIO $ system "rm -rf ./build"
    ignore $ mIO $ system "rm -rf ./main.ipkg"
    ignore $ mIO $ system "rm -rf ./.build"

    mIO $ putStrLn "Cleaned up"
