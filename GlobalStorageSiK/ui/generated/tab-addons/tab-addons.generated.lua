-- Generated data only. Do not edit.
return {
  ["actionAllowlist"] = {
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "addons.open"
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
      ["id"] = "addons.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Addons"
        }
      }
    },
    {
      ["id"] = "addons.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Bahía de periféricos de esta red. Cada tarjeta abre su instalación, nivel o retirada."
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
    ["surfaceSpecSha256"] = "fe0ad9b5a5fbc1199996a432c1ef49920bcad9b00c5d0c5dccda81fe105e672c",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "43385818fad1dd71330fd657ed23a4550073c50f1889225e51bb7d96771efda9",
    ["visualSubtreeSha256"] = "e7c7721718c8825e709b4063298a4779daf88913e1df6f54f7e701efba51d7c8"
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
    ["id"] = "tab-addons",
    ["kind"] = "embedded",
    ["owner"] = {
      ["modulePath"] = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Addons.lua",
      ["repository"] = "global-storage-sik",
      ["symbol"] = "GlobalStorageSiK.TerminalAddons"
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
          ["actions"] = {
            {
              ["actionId"] = "addons.open",
              ["event"] = "activate"
            }
          },
          ["children"] = {},
          ["id"] = "addons-cards",
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
                ["path"] = "addons.cards"
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
      ["id"] = "addons-root",
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
            ["ref"] = "addons.title"
          }
        },
        {
          ["name"] = "help",
          ["value"] = {
            ["kind"] = "i18n",
            ["ref"] = "addons.help"
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
