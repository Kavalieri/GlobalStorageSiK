-- Generated data only. Do not edit.
return {
  ["actionAllowlist"] = {
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "programming.run"
    }
  },
  ["assets"] = {},
  ["capabilities"] = {
    "block.header"
  },
  ["componentFactories"] = {
    {
      ["runtimeFactory"] = "SiK.UI.Block.create",
      ["typeId"] = "block"
    },
    {
      ["runtimeFactory"] = "SiK.UI.CardCollection.create",
      ["typeId"] = "card-collection"
    },
    {
      ["runtimeFactory"] = "SiK.UI.Controls.create",
      ["typeId"] = "control"
    }
  },
  ["documentKind"] = "sik-ui-runtime-surface",
  ["frameworkRef"] = {
    ["id"] = "SiKUIFramework",
    ["manifestSha256"] = "a35db979fef0382a6be5469a1642c763d58b8b4ecb8c3b17040d57f0f088bea6",
    ["manifestVersion"] = "0.1.0-preview",
    ["namespace"] = "SiK.UI"
  },
  ["i18n"] = {
    {
      ["id"] = "programming.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Grabación de disquetes"
        }
      }
    },
    {
      ["id"] = "programming.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Graba programas disponibles en disquetes en blanco desde la red."
        }
      }
    }
  },
  ["product"] = {
    ["id"] = "global-storage-sik",
    ["namespace"] = "GlobalStorageSiK"
  },
  ["profiles"] = {
    {
      ["id"] = "compact",
      ["minViewportHeight"] = 0,
      ["minViewportWidth"] = 0,
      ["safeArea"] = 16
    },
    {
      ["id"] = "standard",
      ["minViewportHeight"] = 700,
      ["minViewportWidth"] = 900,
      ["safeArea"] = 16
    },
    {
      ["id"] = "wide",
      ["minViewportHeight"] = 800,
      ["minViewportWidth"] = 1400,
      ["safeArea"] = 16
    }
  },
  ["provenance"] = {
    ["frameworkManifestSha256"] = "a35db979fef0382a6be5469a1642c763d58b8b4ecb8c3b17040d57f0f088bea6",
    ["generatorSha256"] = "ffa0454ab9bad8b845f2cb8d036d918182a315e7b9c1b7e8f7bf49589da737a4",
    ["schemaSha256"] = "ef8b4a9769c8794563d33ee8fabc8f407504300a36094e1689f0e300286695e5",
    ["surfaceSpecSha256"] = "f4e5f7a85e5254720a58a9b3b5648beec555de6d60c4cc3589ccd0c8c845895f",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "43385818fad1dd71330fd657ed23a4550073c50f1889225e51bb7d96771efda9",
    ["visualSubtreeSha256"] = "eec2be774b1a90407db806793aedecd39ad28e7519b63ec7828ae229df91c1bc"
  },
  ["schemaId"] = "sik-ui-runtime-v1",
  ["schemaVersion"] = 1,
  ["surface"] = {
    ["callers"] = {
      {
        ["modulePath"] = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI.lua",
        ["repository"] = "global-storage-sik",
        ["symbol"] = "GlobalStorageSiK.TerminalUI"
      }
    },
    ["id"] = "tab-programming",
    ["kind"] = "embedded",
    ["owner"] = {
      ["modulePath"] = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Programming.lua",
      ["repository"] = "global-storage-sik",
      ["symbol"] = "GlobalStorageSiK.TerminalProgramming"
    },
    ["profiles"] = {
      "compact",
      "standard",
      "wide"
    },
    ["root"] = {
      ["actions"] = {},
      ["capabilities"] = {
        {
          ["id"] = "block.header",
          ["props"] = {
            {
              ["name"] = "info-visible",
              ["value"] = {
                ["kind"] = "literal",
                ["value"] = true
              }
            }
          }
        }
      },
      ["children"] = {
        {
          ["actions"] = {},
          ["children"] = {},
          ["id"] = "programming-status",
          ["layout"] = {
            ["base"] = {
              {
                ["name"] = "fill",
                ["value"] = {
                  ["kind"] = "literal",
                  ["value"] = true
                }
              }
            },
            ["mode"] = "row",
            ["overrides"] = {}
          },
          ["props"] = {
            {
              ["name"] = "kind",
              ["value"] = {
                ["kind"] = "literal",
                ["value"] = "feedback"
              }
            },
            {
              ["name"] = "data",
              ["value"] = {
                ["kind"] = "data",
                ["path"] = "programming.status"
              }
            }
          },
          ["type"] = "control",
          ["variant"] = "info"
        },
        {
          ["actions"] = {
            {
              ["actionId"] = "programming.run",
              ["event"] = "activate"
            }
          },
          ["children"] = {},
          ["id"] = "programming-cards",
          ["layout"] = {
            ["base"] = {
              {
                ["name"] = "fill",
                ["value"] = {
                  ["kind"] = "literal",
                  ["value"] = true
                }
              },
              {
                ["name"] = "grow",
                ["value"] = {
                  ["kind"] = "literal",
                  ["value"] = 1
                }
              }
            },
            ["mode"] = "column",
            ["overrides"] = {}
          },
          ["props"] = {
            {
              ["name"] = "items",
              ["value"] = {
                ["kind"] = "data",
                ["path"] = "programming.cards"
              }
            },
            {
              ["name"] = "maxColumns",
              ["value"] = {
                ["kind"] = "literal",
                ["value"] = 2
              }
            },
            {
              ["name"] = "columns",
              ["value"] = {
                ["kind"] = "literal",
                ["value"] = 2
              }
            },
            {
              ["name"] = "exactColumns",
              ["value"] = {
                ["kind"] = "literal",
                ["value"] = true
              }
            }
          },
          ["type"] = "card-collection",
          ["variant"] = "summary"
        }
      },
      ["id"] = "programming-root",
      ["layout"] = {
        ["base"] = {
          {
            ["name"] = "fill",
            ["value"] = {
              ["kind"] = "literal",
              ["value"] = true
            }
          },
          {
            ["name"] = "gap",
            ["value"] = {
              ["kind"] = "token",
              ["ref"] = "spacing.8"
            }
          }
        },
        ["mode"] = "column",
        ["overrides"] = {}
      },
      ["props"] = {
        {
          ["name"] = "title",
          ["value"] = {
            ["kind"] = "i18n",
            ["ref"] = "programming.title"
          }
        },
        {
          ["name"] = "help",
          ["value"] = {
            ["kind"] = "i18n",
            ["ref"] = "programming.help"
          }
        }
      },
      ["type"] = "block",
      ["variant"] = "fill"
    }
  },
  ["surfaceReferences"] = {},
  ["tokens"] = {
    {
      ["id"] = "spacing.8",
      ["kind"] = "number",
      ["runtime"] = true,
      ["value"] = 8
    }
  }
}
