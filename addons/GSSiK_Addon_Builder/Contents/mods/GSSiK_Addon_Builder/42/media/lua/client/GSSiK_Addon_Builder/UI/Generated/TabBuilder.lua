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
    ["manifestSha256"] = "9be0e45d500be678ed17f628d151c164b83d3673097f3d8c53eacc0115590c74",
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
    ["frameworkManifestSha256"] = "9be0e45d500be678ed17f628d151c164b83d3673097f3d8c53eacc0115590c74",
    ["generatorSha256"] = "b680dfefc17e687bb2839cb5f589d64cf0da07fff454a4ee26e002333eee73ae",
    ["schemaSha256"] = "ef8b4a9769c8794563d33ee8fabc8f407504300a36094e1689f0e300286695e5",
    ["surfaceSpecSha256"] = "3e3e5c0bf0f0200dcff8933838ed829fcc06f245e6e2953a89301fb3e841b012",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "fdc0af9ddac5bf72956e5174a31d7904e2dfd83fb15f26c032bb19b055dc87e5",
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
