import java.io.Reader;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/** Small, bounded host for the real Project Zomboid Kahlua runtime. */
public final class CatalogTransportKahluaHost {
    private CatalogTransportKahluaHost() {}

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            throw new IllegalArgumentException("usage: CatalogTransportKahluaHost <projectzomboid.jar> <runner.lua> <codec.lua>");
        }
        Path jar = Path.of(args[0]).toAbsolutePath().normalize();
        Path runner = Path.of(args[1]).toAbsolutePath().normalize();
        Path codec = Path.of(args[2]).toAbsolutePath().normalize();
        if (!Files.isRegularFile(jar) || !Files.isRegularFile(runner) || !Files.isRegularFile(codec)) {
            throw new IllegalArgumentException("missing jar, runner or codec: " + jar + " / " + runner + " / " + codec);
        }
        Class<?> platformType = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Object platform = platformType.getMethod("getInstance").invoke(null);
        Object environment = platformType.getMethod("newEnvironment").invoke(platform);
        platformType.getMethod("setupEnvironment", Class.forName("se.krka.kahlua.vm.KahluaTable"))
                .invoke(platform, environment);
        Class<?> tableType = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Object packageTable = tableType.getMethod("rawget", Object.class).invoke(environment, "package");
        if (packageTable != null) {
            tableType.getMethod("rawset", Object.class, Object.class).invoke(
                    packageTable, "path", codec.getParent().resolve("?.lua").toString());
        }
        tableType.getMethod("rawset", Object.class, Object.class).invoke(
                environment, "CATALOG_CODEC_PATH", codec.toString());
        Class<?> threadType = Class.forName("se.krka.kahlua.vm.KahluaThread");
        Object thread = threadType.getConstructor(PrintStream.class,
                Class.forName("se.krka.kahlua.vm.Platform"), tableType)
                .newInstance(System.out, platform, environment);
        threadType.getField("debugOwnerThread").set(thread, Thread.currentThread());
        Class<?> compilerType = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
        try (Reader codecSource = Files.newBufferedReader(codec, StandardCharsets.UTF_8)) {
            Object codecClosure = compilerType.getMethod("loadis", Reader.class, String.class, tableType)
                    .invoke(null, codecSource, codec.toString(), environment);
            Object codecValue = threadType.getMethod("call", Object.class, Object[].class)
                    .invoke(thread, codecClosure, new Object[0]);
            tableType.getMethod("rawset", Object.class, Object.class).invoke(
                    environment, "CATALOG_CODEC", codecValue);
        }
        try (Reader source = Files.newBufferedReader(runner, StandardCharsets.UTF_8)) {
            Object closure = compilerType.getMethod("loadis", Reader.class, String.class, tableType)
                    .invoke(null, source, runner.toString(), environment);
            threadType.getMethod("call", Object.class, Object[].class)
                    .invoke(thread, closure, new Object[0]);
        }
    }
}
