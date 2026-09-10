-- Generated data only. Do not edit.
return {
  ["actionAllowlist"] = {
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "craft.open-main"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "craft.open-cook"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "craft.toggle-destination"
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
      ["id"] = "craft.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Crafteo remoto"
        }
      }
    },
    {
      ["id"] = "craft.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Usa los recursos disponibles de la red."
        }
      }
    }
  },
  ["product"] = {
    ["id"] = "gssik-addon-craft",
    ["namespace"] = "GSSiK_Addon_Craft"
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
    ["surfaceSpecSha256"] = "56e2499ef4c680646362e8d6b56ce187bf3db00f296552f6c3e3113332079888",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "4c7de7d07baf52992f1c29b45cffc44a8ff46f734c397995c1f5af346edb2f3a",
    ["visualSubtreeSha256"] = "09af53f74d8b483706fa1ad8b14e2a6f30834fef2b1e14f9412c956315fc3cb3"
  },
  ["schemaId"] = "sik-ui-runtime-v1",
  ["schemaVersion"] = 1,
  ["surface"] = {
    ["callers"] = {
      {
        ["modulePath"] = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/client/GSSiK_Addon_Craft_Client.lua",
        ["repository"] = "global-storage-sik",
        ["symbol"] = "Terminal.registerTab"
      }
    },
    ["id"] = "tab-craft",
    ["kind"] = "embedded",
    ["owner"] = {
      ["modulePath"] = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/client/GSSiK_Addon_Craft_TerminalUI.lua",
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
              ["id"] = "craft-status",
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
                    ["path"] = "craft.status"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "status"
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "craft-warning",
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
                    ["path"] = "craft.warning"
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
              ["children"] = {
                {
                  ["actions"] = {},
                  ["children"] = {},
                  ["id"] = "craft-interface",
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
                        ["path"] = "craft.interface"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "copy"
                },
                {
                  ["actions"] = {},
                  ["children"] = {},
                  ["id"] = "craft-cook-state",
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
                        ["path"] = "craft.cook"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "copy"
                }
              },
              ["id"] = "craft-info",
              ["layout"] = {
                ["base"] = {
                  {
                    ["name"] = "columns",
                    ["value"] = {
                      ["kind"] = "literal",
                      ["value"] = 2
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
                ["mode"] = "grid",
                ["overrides"] = {
                  {
                    ["bindings"] = {
                      {
                        ["name"] = "columns",
                        ["value"] = {
                          ["kind"] = "literal",
                          ["value"] = 1
                        }
                      }
                    },
                    ["profileId"] = "compact"
                  }
                }
              },
              ["props"] = {},
              ["type"] = "container",
              ["variant"] = "grid"
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "craft.open-main",
                  ["event"] = "activate"
                }
              },
              ["children"] = {},
              ["id"] = "craft-open",
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
                    ["path"] = "craft.openMain"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "full"
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "craft.open-cook",
                  ["event"] = "activate"
                }
              },
              ["children"] = {},
              ["id"] = "craft-open-cook",
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
                    ["path"] = "craft.openCook"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "full",
              ["visual"] = {
                ["visibleWhen"] = "cook-available"
              }
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "craft.toggle-destination",
                  ["event"] = "activate"
                }
              },
              ["children"] = {},
              ["id"] = "craft-destination",
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
                    ["path"] = "craft.destination"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "full"
            }
          },
          ["id"] = "craft-block",
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
                ["ref"] = "craft.title"
              }
            },
            {
              ["name"] = "help",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "craft.help"
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
      ["id"] = "craft-root",
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
