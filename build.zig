const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .unwind_tables = .none,
        .single_threaded = true,
    });
    exe_mod.addWin32ResourceFile(.{ .file = b.path("main.rc") });

    const res = b.addWriteFiles();
    const manifest_file = res.add("main.manifest", manifest);

    const exe = b.addExecutable(.{
        .name = "LibreScroll",
        .root_module = exe_mod,
        .win32_manifest = manifest_file ,
    });
    exe.subsystem = @enumFromInt(1); // windows subsystem

    b.installArtifact(exe);

    const zip_name = "LibreScroll-" ++ @import("main.zig").LIBRE_SCROLL_VERSION_TEXT ++ ".zip";
    const release_build = b.addSystemCommand(&.{ "zig", "build", "--release=small", "-Dtarget=x86_64-windows-gnu" });
    const release_zip = b.addSystemCommand(&.{ "tar", "-caf", "zig-out/" ++ zip_name, "-C", "zig-out/bin", "LibreScroll.exe" });
    const release_step = b.step("release", "build release artifact");
    release_zip.step.dependOn(&release_build.step);
    release_step.dependOn(&release_zip.step);
}

const manifest = 
\\<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
\\<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
\\    <dependency>
\\        <dependentAssembly>
\\            <assemblyIdentity
\\                type="win32"
\\                name="Microsoft.Windows.Common-Controls"
\\                version="6.0.0.0"
\\                processorArchitecture="*"
\\                publicKeyToken="6595b64144ccf1df"
\\                language="*"
\\            />
\\        </dependentAssembly>
\\    </dependency>
\\</assembly>
;