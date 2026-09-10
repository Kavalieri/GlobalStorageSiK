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
      ["runtimeFactory"] = "SiK.UI.Container.create",
      ["typeId"] = "container"
    },
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
    ["manifestSha256"] = "9be0e45d500be678ed17f628d151c164b83d3673097f3d8c53eacc0115590c74",
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
    },
    {
      ["id"] = "programming.resources.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Recursos de grabación"
        }
      }
    },
    {
      ["id"] = "programming.programs.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Programas"
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
    ["frameworkManifestSha256"] = "9be0e45d500be678ed17f628d151c164b83d3673097f3d8c53eacc0115590c74",
    ["generatorSha256"] = "b680dfefc17e687bb2839cb5f589d64cf0da07fff454a4ee26e002333eee73ae",
    ["schemaSha256"] = "ef8b4a9769c8794563d33ee8fabc8f407504300a36094e1689f0e300286695e5",
    ["surfaceSpecSha256"] = "8e1a9d9e15e073a56ccf45224ae35e48cf16d1c7c0c8582e0d08252031f392ff",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "fdc0af9ddac5bf72956e5174a31d7904e2dfd83fb15f26c032bb19b055dc87e5",
    ["visualSubtreeSha256"] = "3f4b81a82072b0c54493011b5c3712fcd923afd2cc85d4b78e95347534ceb49a"
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
      ["capabilities"] = {},
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
              ["children"] = {
                {
                  ["actions"] = {},
                  ["children"] = {},
                  ["id"] = "programming-reader-resource",
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
                      ["name"] = "kind",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = "requirement-row"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "programming.resources.reader"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "resource"
                },
                {
                  ["actions"] = {},
                  ["children"] = {},
                  ["id"] = "programming-blank-disk-resource",
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
                      ["name"] = "kind",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = "requirement-row"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "programming.resources.blankDisk"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "resource"
                }
              },
              ["id"] = "programming-resources-row",
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
                ["mode"] = "row",
                ["overrides"] = {}
              },
              ["props"] = {},
              ["type"] = "container",
              ["variant"] = "resource-row"
            }
          },
          ["id"] = "programming-resources",
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
            ["mode"] = "column",
            ["overrides"] = {}
          },
          ["props"] = {
            {
              ["name"] = "title",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "programming.resources.title"
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
          ["variant"] = "standard"
        },
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
              ["variant"] = "output"
            }
          },
          ["id"] = "programming-programs",
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
            ["mode"] = "column",
            ["overrides"] = {}
          },
          ["props"] = {
            {
              ["name"] = "title",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "programming.programs.title"
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
          ["variant"] = "standard"
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
          ["name"] = "direction",
          ["value"] = {
            ["kind"] = "literal",
            ["value"] = "column"
          }
        },
        {
          ["name"] = "overflow",
          ["value"] = {
            ["kind"] = "literal",
            ["value"] = "scroll"
          }
        }
      },
      ["type"] = "container",
      ["variant"] = "surface-root"
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
