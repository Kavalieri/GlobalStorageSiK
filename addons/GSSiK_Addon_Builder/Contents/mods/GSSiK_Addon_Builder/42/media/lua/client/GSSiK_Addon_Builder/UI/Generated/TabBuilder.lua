-- Generated data only. Do not edit.
return {
  ["actionAllowlist"] = {
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "builder.open-main"
    }
  },
  ["assets"] = {},
  ["capabilities"] = {
    "block.header"
  },
  ["componentFactories"] = {
    {
      ["runtimeFactory"] = "SiK.UI.Container.create",
      ["typeId"] = "container"
    },
    {
      ["runtimeFactory"] = "SiK.UI.Block.create",
      ["typeId"] = "block"
    },
    {
      ["runtimeFactory"] = "SiK.UI.Controls.create",
      ["typeId"] = "control"
    }
  },
  ["documentKind"] = "sik-ui-runtime-surface",
  ["frameworkRef"] = {
    ["id"] = "SiKUIFramework",
    ["manifestSha256"] = "2cca88b2efa1f44f02bae6d86aef44131bbd212a002c9b439c6d5d673505b063",
    ["manifestVersion"] = "0.1.0-preview",
    ["namespace"] = "SiK.UI"
  },
  ["i18n"] = {
    {
      ["id"] = "builder.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Construcción remota"
        }
      }
    },
    {
      ["id"] = "builder.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Usa los recursos disponibles de la red."
        }
      }
    }
  },
  ["product"] = {
    ["id"] = "gssik-addon-builder",
    ["namespace"] = "GSSiK_Addon_Builder"
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
    ["frameworkManifestSha256"] = "2cca88b2efa1f44f02bae6d86aef44131bbd212a002c9b439c6d5d673505b063",
    ["generatorSha256"] = "b680dfefc17e687bb2839cb5f589d64cf0da07fff454a4ee26e002333eee73ae",
    ["schemaSha256"] = "ef8b4a9769c8794563d33ee8fabc8f407504300a36094e1689f0e300286695e5",
    ["surfaceSpecSha256"] = "b7cb9b7ac3dce95c0b5f0623f52b6d4e3d87f2c916dc62d0536e08a9515d7cf3",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "6bb257f3a71d7e213401da9d67bce105b52b39fa2dbd667878f2e8baaf3c1a43",
    ["visualSubtreeSha256"] = "2b86e7f2bf052c736234ea4c9f156e4ee5927c34dbf305a5130c70587126b48c"
  },
  ["schemaId"] = "sik-ui-runtime-v1",
  ["schemaVersion"] = 1,
  ["surface"] = {
    ["callers"] = {
      {
        ["modulePath"] = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/client/GSSiK_Addon_Builder_Client.lua",
        ["repository"] = "global-storage-sik",
        ["symbol"] = "Terminal.registerTab"
      }
    },
    ["id"] = "tab-builder",
    ["kind"] = "embedded",
    ["owner"] = {
      ["modulePath"] = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/client/GSSiK_Addon_Builder_TerminalUI.lua",
      ["repository"] = "global-storage-sik",
      ["symbol"] = "TerminalModule"
    },
    ["profiles"] = {
      "compact",
      "standard",
      "wide"
    },
    ["root"] = {
      ["actions"] = {},
      ["children"] = {
        {
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
              ["id"] = "builder-status",
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
                    ["path"] = "builder.status"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "status"
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "builder-warning",
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
                    ["path"] = "builder.warning"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "warning",
              ["visual"] = {
                ["visibleWhen"] = "has-warning"
              }
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "builder-interface",
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
                    ["value"] = "status"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "builder.interface"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "copy"
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "builder.open-main",
                  ["event"] = "activate"
                }
              },
              ["children"] = {},
              ["id"] = "builder-open",
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
                    ["value"] = "button"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "builder.openMain"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "full"
            }
          },
          ["id"] = "builder-block",
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
                ["ref"] = "builder.title"
              }
            },
            {
              ["name"] = "help",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "builder.help"
              }
            },
            {
              ["name"] = "scrollable",
              ["value"] = {
                ["kind"] = "literal",
                ["value"] = true
              }
            }
          },
          ["type"] = "block",
          ["variant"] = "fill"
        }
      },
      ["id"] = "builder-root",
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
      ["props"] = {},
      ["type"] = "container",
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
