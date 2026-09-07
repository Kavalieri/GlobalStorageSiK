-- Generated data only. Do not edit.
return {
  ["actionAllowlist"] = {
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "network.create-room"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "network.create-building"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "network.create-selection"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "network.activate-row"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "network.rescan"
    }
  },
  ["assets"] = {},
  ["capabilities"] = {
    "table.expandable",
    "table.row-interactions",
    "block.header"
  },
  ["componentFactories"] = {
    {
      ["runtimeFactory"] = "SiK.UI.Container.create",
      ["typeId"] = "container"
    },
    {
      ["runtimeFactory"] = "SiK.UI.Table.create",
      ["typeId"] = "table"
    },
    {
      ["runtimeFactory"] = "SiK.UI.Block.create",
      ["typeId"] = "block"
    },
    {
      ["runtimeFactory"] = "SiK.UI.ActionGroup.create",
      ["typeId"] = "action-group"
    },
    {
      ["runtimeFactory"] = "SiK.UI.Controls.create",
      ["typeId"] = "control"
    }
  },
  ["documentKind"] = "sik-ui-runtime-surface",
  ["frameworkRef"] = {
    ["id"] = "SiKUIFramework",
    ["manifestSha256"] = "0a1107442861c28bdbcdd8145bae7b2fdd2146d948b6382f1a023a6f6ee581ad",
    ["manifestVersion"] = "0.1.0-preview",
    ["namespace"] = "SiK.UI"
  },
  ["i18n"] = {
    {
      ["id"] = "network.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Zonas y nodos"
        }
      }
    },
    {
      ["id"] = "network.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Crea zonas y configura sus contenedores. Orden de destino: primero debe pasar las reglas de zona; una regla propia válida gana a Global; entre destinos igual de específicos se evalúa la prioridad menor, primero de zona y después de contenedor; si empatan, decide la afinidad con el objeto."
        }
      }
    },
    {
      ["id"] = "network.create.room",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Esta habitación"
        }
      }
    },
    {
      ["id"] = "network.create.building",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Todo el edificio"
        }
      }
    },
    {
      ["id"] = "network.create.selection",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Selección personalizada"
        }
      }
    },
    {
      ["id"] = "network.column.name",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Nombre"
        }
      }
    },
    {
      ["id"] = "network.column.protocol",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Protocolo"
        }
      }
    },
    {
      ["id"] = "network.column.priority",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Prio."
        }
      }
    },
    {
      ["id"] = "network.column.status",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Estado"
        }
      }
    },
    {
      ["id"] = "network.column.occupancy",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "%"
        }
      }
    },
    {
      ["id"] = "network.rescan.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Reescaneo de toda la red"
        }
      }
    },
    {
      ["id"] = "network.rescan.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Control administrativo de recuperación. Revisa todas las zonas para detectar contenedores nuevos, sustituidos, ausentes o modificados."
        }
      }
    },
    {
      ["id"] = "network.rescan.action",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Reescanear toda la red"
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
    ["frameworkManifestSha256"] = "0a1107442861c28bdbcdd8145bae7b2fdd2146d948b6382f1a023a6f6ee581ad",
    ["generatorSha256"] = "151a7bcc388869c774c9e65eb30d478f5894e7a5d25c1791718b9cfd2881ba3b",
    ["schemaSha256"] = "ef8b4a9769c8794563d33ee8fabc8f407504300a36094e1689f0e300286695e5",
    ["surfaceSpecSha256"] = "ddb1402e141d1a5d6748828dc9c411948063f518e0a30a7816219475fb7d8338",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "c24833957e26b083bb87adef8608cde8e50dff16e6cfc03f5123feb73b6dabef",
    ["visualSubtreeSha256"] = "13cda2937e033d43b44568de0f0a2e86fb3e83831593db2e3cecfba8c8f59ac6"
  },
  ["schemaId"] = "sik-ui-runtime-v1",
  ["schemaVersion"] = 1,
  ["surface"] = {
    ["callers"] = {
      {
        ["modulePath"] = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI.lua",
        ["repository"] = "global-storage-sik",
        ["symbol"] = "GlobalStorageSiK.TerminalNetwork.buildZonesSection"
      }
    },
    ["id"] = "tab-red",
    ["kind"] = "embedded",
    ["owner"] = {
      ["modulePath"] = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Network.lua",
      ["repository"] = "global-storage-sik",
      ["symbol"] = "GlobalStorageSiK.TerminalNetwork"
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
            },
            {
              ["name"] = "actions",
              ["value"] = {
                ["kind"] = "data",
                ["path"] = "network.headerActions"
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
              ["children"] = {
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "network.create-room",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "network-create-room",
                  ["layout"] = {
                    ["base"] = {
                      {
                        ["name"] = "grow",
                        ["value"] = {
                          ["kind"] = "literal",
                          ["value"] = 1
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
                      ["name"] = "label",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "network.create.room"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "network.createRoom"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "active"
                },
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "network.create-building",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "network-create-building",
                  ["layout"] = {
                    ["base"] = {
                      {
                        ["name"] = "grow",
                        ["value"] = {
                          ["kind"] = "literal",
                          ["value"] = 1
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
                      ["name"] = "label",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "network.create.building"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "network.createBuilding"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                },
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "network.create-selection",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "network-create-selection",
                  ["layout"] = {
                    ["base"] = {
                      {
                        ["name"] = "grow",
                        ["value"] = {
                          ["kind"] = "literal",
                          ["value"] = 1
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
                      ["name"] = "label",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "network.create.selection"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "network.createSelection"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                }
              },
              ["id"] = "network-create-actions",
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
              ["props"] = {
                {
                  ["name"] = "mode",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = "equal"
                  }
                }
              },
              ["type"] = "action-group",
              ["variant"] = "equal"
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "network.activate-row",
                  ["event"] = "activate"
                }
              },
              ["capabilities"] = {
                {
                  ["id"] = "table.expandable",
                  ["props"] = {
                    {
                      ["name"] = "expandable",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = true
                      }
                    },
                    {
                      ["name"] = "depth",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = 2
                      }
                    },
                    {
                      ["name"] = "connectors",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = true
                      }
                    },
                    {
                      ["name"] = "child-pagination",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = false
                      }
                    }
                  }
                },
                {
                  ["id"] = "table.row-interactions",
                  ["props"] = {
                    {
                      ["name"] = "adapter",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = "context.tableOptions"
                      }
                    },
                    {
                      ["name"] = "tooltip",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = true
                      }
                    },
                    {
                      ["name"] = "contextMenu",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = false
                      }
                    },
                    {
                      ["name"] = "drag",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = false
                      }
                    },
                    {
                      ["name"] = "exactSelection",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = true
                      }
                    }
                  }
                }
              },
              ["children"] = {},
              ["columns"] = {
                {
                  ["align"] = "left",
                  ["flex"] = 1,
                  ["key"] = "name",
                  ["labelRef"] = "network.column.name",
                  ["min"] = 120
                },
                {
                  ["align"] = "left",
                  ["flex"] = 1.7,
                  ["key"] = "protocol",
                  ["labelRef"] = "network.column.protocol",
                  ["min"] = 180
                },
                {
                  ["align"] = "center",
                  ["key"] = "priority",
                  ["labelRef"] = "network.column.priority",
                  ["width"] = 60
                },
                {
                  ["align"] = "center",
                  ["key"] = "status",
                  ["labelRef"] = "network.column.status",
                  ["width"] = 76
                },
                {
                  ["align"] = "right",
                  ["key"] = "occupancy",
                  ["labelRef"] = "network.column.occupancy",
                  ["width"] = 60
                }
              },
              ["id"] = "network-table",
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
                  },
                  {
                    ["name"] = "clip",
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
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "network.rows"
                  }
                }
              },
              ["type"] = "table",
              ["variant"] = "hierarchical"
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
                    },
                    {
                      ["name"] = "actions",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "network.rescanHeaderActions"
                      }
                    }
                  }
                }
              },
              ["children"] = {
                {
                  ["actions"] = {},
                  ["children"] = {},
                  ["id"] = "network-rescan-feedback",
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
                        ["value"] = "alert-row"
                      }
                    },
                    {
                      ["name"] = "icon-key",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = "sik.alert.warning.24"
                      }
                    },
                    {
                      ["name"] = "size",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = 24
                      }
                    },
                    {
                      ["name"] = "glow",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = true
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "network.rescanFeedback"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "warning",
                  ["visual"] = {
                    ["visibleWhen"] = "network-rescan-has-incident"
                  }
                },
                {
                  ["actions"] = {},
                  ["children"] = {},
                  ["id"] = "network-rescan-progress",
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
                        ["value"] = "alert-row"
                      }
                    },
                    {
                      ["name"] = "icon-key",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = "sik.alert.warning.24"
                      }
                    },
                    {
                      ["name"] = "size",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = 24
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "network.scanProgress"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "scan",
                  ["visual"] = {
                    ["visibleWhen"] = "network-scan-running"
                  }
                },
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "network.rescan",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "network-rescan-action",
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
                      ["name"] = "label",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "network.rescan.action"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "network.rescanAction"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                }
              },
              ["id"] = "network-rescan-block",
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
                    ["ref"] = "network.rescan.title"
                  }
                },
                {
                  ["name"] = "help",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "network.rescan.help"
                  }
                },
                {
                  ["name"] = "scrollable",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = false
                  }
                }
              },
              ["type"] = "block",
              ["variant"] = "standard",
              ["visual"] = {
                ["visibleWhen"] = "network-rescan-visible"
              }
            }
          },
          ["id"] = "network-content",
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
                ["value"] = "clip"
              }
            }
          },
          ["type"] = "container",
          ["variant"] = "stack"
        }
      },
      ["id"] = "network-root",
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
            ["ref"] = "network.title"
          }
        },
        {
          ["name"] = "help",
          ["value"] = {
            ["kind"] = "i18n",
            ["ref"] = "network.help"
          }
        },
        {
          ["name"] = "scrollable",
          ["value"] = {
            ["kind"] = "literal",
            ["value"] = false
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
