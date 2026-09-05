-- Generated data only. Do not edit.
return {
  ["actionAllowlist"] = {
    {
      ["events"] = {
        "change"
      },
      ["id"] = "options.select-network"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "options.use-network"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "options.refresh-networks"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "options.open-terminal"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "options.open-member"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "options.claim-ownership"
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "options.select-access"
    },
    {
      ["events"] = {
        "activate",
        "submit"
      },
      ["id"] = "options.add-access"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "options.change-palette"
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
      ["runtimeFactory"] = "SiK.UI.Table.create",
      ["typeId"] = "table"
    },
    {
      ["runtimeFactory"] = "SiK.UI.Block.create",
      ["typeId"] = "block"
    },
    {
      ["runtimeFactory"] = "SiK.UI.Form.create",
      ["typeId"] = "form"
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
    ["manifestSha256"] = "0a1107442861c28bdbcdd8145bae7b2fdd2146d948b6382f1a023a6f6ee581ad",
    ["manifestVersion"] = "0.1.0-preview",
    ["namespace"] = "SiK.UI"
  },
  ["i18n"] = {
    {
      ["id"] = "options.state.network.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Red seleccionada"
        }
      }
    },
    {
      ["id"] = "options.state.network.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Selecciona una red accesible para esta sesión. Usar red no inicia un reescaneo ni modifica la configuración compartida."
        }
      }
    },
    {
      ["id"] = "options.state.network.current",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Red actual"
        }
      }
    },
    {
      ["id"] = "options.state.network.selected",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Red seleccionada"
        }
      }
    },
    {
      ["id"] = "options.state.network.use",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Usar seleccionada"
        }
      }
    },
    {
      ["id"] = "options.state.network.refresh",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Actualizar lista"
        }
      }
    },
    {
      ["id"] = "options.state.operational.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Estado operativo"
        }
      }
    },
    {
      ["id"] = "options.state.operational.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Resume las cuatro condiciones que permiten usar esta red. Cada indicador cambia con el estado autoritativo recibido."
        }
      }
    },
    {
      ["id"] = "options.state.operational.power",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Energía disponible"
        }
      }
    },
    {
      ["id"] = "options.state.operational.terminal",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Terminal detectado"
        }
      }
    },
    {
      ["id"] = "options.state.operational.zones",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Zonas listas"
        }
      }
    },
    {
      ["id"] = "options.state.operational.access",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Acceso disponible"
        }
      }
    },
    {
      ["id"] = "options.state.resources.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Recursos y actividad"
        }
      }
    },
    {
      ["id"] = "options.state.resources.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Muestra la actividad agregada de la red, el modo de acceso, el consumo y la capacidad recibidos del estado actual."
        }
      }
    },
    {
      ["id"] = "options.state.resources.summary",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Nodos y tipos"
        }
      }
    },
    {
      ["id"] = "options.state.resources.access",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Acceso"
        }
      }
    },
    {
      ["id"] = "options.state.resources.consumption",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Consumo"
        }
      }
    },
    {
      ["id"] = "options.state.resources.capacity-available",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Capacidad de red"
        }
      }
    },
    {
      ["id"] = "options.state.resources.capacity",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Capacidad"
        }
      }
    },
    {
      ["id"] = "options.state.resources.warning",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Estimación parcial"
        }
      }
    },
    {
      ["id"] = "options.state.range.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Alcance"
        }
      }
    },
    {
      ["id"] = "options.state.range.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Distingue la distancia desde la que puede usarse esta terminal y el radio físico cubierto por la red."
        }
      }
    },
    {
      ["id"] = "options.state.range.terminal",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Uso del terminal"
        }
      }
    },
    {
      ["id"] = "options.state.range.network",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Alcance de red"
        }
      }
    },
    {
      ["id"] = "options.state.palette.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Paleta de interfaz"
        }
      }
    },
    {
      ["id"] = "options.state.palette.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Preferencia visual local por personaje. Solo modifica colores neutrales; estados, peligro y operadores conservan su significado."
        }
      }
    },
    {
      ["id"] = "options.admin.terminals.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Terminales"
        }
      }
    },
    {
      ["id"] = "options.admin.terminals.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Lista los terminales registrados. Pulsa una fila para renombrar, cambiar el principal, suspender o retirar ese terminal."
        }
      }
    },
    {
      ["id"] = "options.admin.column.terminal-name",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Nombre"
        }
      }
    },
    {
      ["id"] = "options.admin.column.coordinates",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Coordenadas"
        }
      }
    },
    {
      ["id"] = "options.admin.column.terminal-role",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Rol"
        }
      }
    },
    {
      ["id"] = "options.admin.column.status",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Estado"
        }
      }
    },
    {
      ["id"] = "options.admin.members.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Miembros"
        }
      }
    },
    {
      ["id"] = "options.admin.members.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Muestra rol y última conexión. Pulsa una fila para gestionar rol, zonas permitidas, propiedad o retirada de acceso."
        }
      }
    },
    {
      ["id"] = "options.admin.column.member-role",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Rol"
        }
      }
    },
    {
      ["id"] = "options.admin.column.member-name",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Nombre"
        }
      }
    },
    {
      ["id"] = "options.admin.column.connection",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Última conexión"
        }
      }
    },
    {
      ["id"] = "options.admin.succession.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "La propiedad se conserva mejor cuando existe otro administrador con acceso."
        }
      }
    },
    {
      ["id"] = "options.admin.succession.warning",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Conviene mantener al menos otro administrador con acceso."
        }
      }
    },
    {
      ["id"] = "options.admin.claim",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Reclamar propiedad"
        }
      }
    },
    {
      ["id"] = "options.admin.access.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Añadir acceso"
        }
      }
    },
    {
      ["id"] = "options.admin.access.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Concede acceso a un jugador o a una facción disponible."
        }
      }
    },
    {
      ["id"] = "options.admin.access.select",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Selecciona jugador o facción"
        }
      }
    },
    {
      ["id"] = "options.admin.access.add",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Añadir"
        }
      }
    },
    {
      ["id"] = "options.admin.access.empty",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Nada seleccionado."
        }
      }
    },
    {
      ["id"] = "options.summary.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Resumen"
        }
      }
    },
    {
      ["id"] = "options.summary.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Resume capacidad, composición, energía y alcance de la red actual."
        }
      }
    },
    {
      ["id"] = "options.summary.information.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Información"
        }
      }
    },
    {
      ["id"] = "options.summary.information.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Muestra la capacidad total y las cantidades generales de la red."
        }
      }
    },
    {
      ["id"] = "options.summary.energy.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Energía"
        }
      }
    },
    {
      ["id"] = "options.summary.energy.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Indica si la red detecta un suministro eléctrico utilizable."
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
    ["surfaceSpecSha256"] = "2efdfaaf1c684377295a6217d15986024d1a01da3c18fb281f48a465253bb844",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "797642dd24770b3737dc3466c73889f22d6ea929dec4b9ce0d384a49dd1ee1e1",
    ["visualSubtreeSha256"] = "8c250c9db8afec2ee5edd8a5544f6ebcb8d86654aa9e7298b505eb4cbc5c5455"
  },
  ["schemaId"] = "sik-ui-runtime-v1",
  ["schemaVersion"] = 1,
  ["surface"] = {
    ["callers"] = {
      {
        ["modulePath"] = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI.lua",
        ["repository"] = "global-storage-sik",
        ["symbol"] = "GlobalStorageSiK.TerminalOptions.buildSection"
      }
    },
    ["id"] = "tab-options",
    ["kind"] = "embedded",
    ["owner"] = {
      ["modulePath"] = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Options.lua",
      ["repository"] = "global-storage-sik",
      ["symbol"] = "GlobalStorageSiK.TerminalOptions"
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
              ["actions"] = {
                {
                  ["actionId"] = "options.select-network",
                  ["event"] = "change"
                }
              },
              ["children"] = {},
              ["id"] = "options-network-selector",
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
              ["options"] = {
                {
                  ["id"] = "available",
                  ["labelRef"] = "options.state.network.selected",
                  ["value"] = "available"
                }
              },
              ["props"] = {
                {
                  ["name"] = "kind",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = "combo"
                  }
                },
                {
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.state.network.selected"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.state.selectedNetwork"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default"
            },
            {
              ["actions"] = {},
              ["children"] = {
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "options.use-network",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-network-use",
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
                        ["ref"] = "options.state.network.use"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                },
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "options.refresh-networks",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-network-refresh",
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
                        ["ref"] = "options.state.network.refresh"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                }
              },
              ["id"] = "options-network-actions",
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
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.state.networkActions"
                  }
                }
              },
              ["type"] = "form",
              ["variant"] = "equal-actions"
            }
          },
          ["id"] = "options-network-block",
          ["layout"] = {
            ["base"] = {
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
                ["ref"] = "options.state.network.title"
              }
            },
            {
              ["name"] = "help",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "options.state.network.help"
              }
            }
          },
          ["type"] = "block",
          ["variant"] = "accent"
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
                      ["id"] = "options-capacity",
                      ["layout"] = {
                        ["base"] = {
                          {
                            ["name"] = "span",
                            ["value"] = {
                              ["kind"] = "literal",
                              ["value"] = 4
                            }
                          },
                          {
                            ["name"] = "fill",
                            ["value"] = {
                              ["kind"] = "literal",
                              ["value"] = true
                            }
                          }
                        },
                        ["mode"] = "row",
                        ["overrides"] = {
                          {
                            ["bindings"] = {
                              {
                                ["name"] = "span",
                                ["value"] = {
                                  ["kind"] = "literal",
                                  ["value"] = 2
                                }
                              }
                            },
                            ["profileId"] = "compact"
                          }
                        }
                      },
                      ["props"] = {
                        {
                          ["name"] = "kind",
                          ["value"] = {
                            ["kind"] = "literal",
                            ["value"] = "progress"
                          }
                        },
                        {
                          ["name"] = "data",
                          ["value"] = {
                            ["kind"] = "data",
                            ["path"] = "options.state.capacity"
                          }
                        }
                      },
                      ["type"] = "control",
                      ["variant"] = "capacity"
                    },
                    {
                      ["actions"] = {},
                      ["children"] = {},
                      ["id"] = "options-info-terminals",
                      ["layout"] = {
                        ["base"] = {},
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
                            ["path"] = "options.state.terminalStatus"
                          }
                        }
                      },
                      ["type"] = "control",
                      ["variant"] = "default"
                    },
                    {
                      ["actions"] = {},
                      ["children"] = {},
                      ["id"] = "options-info-zones",
                      ["layout"] = {
                        ["base"] = {},
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
                            ["path"] = "options.state.zonesStatus"
                          }
                        }
                      },
                      ["type"] = "control",
                      ["variant"] = "default"
                    },
                    {
                      ["actions"] = {},
                      ["children"] = {},
                      ["id"] = "options-info-containers",
                      ["layout"] = {
                        ["base"] = {},
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
                            ["path"] = "options.state.resourceSummary"
                          }
                        }
                      },
                      ["type"] = "control",
                      ["variant"] = "default"
                    },
                    {
                      ["actions"] = {},
                      ["children"] = {},
                      ["id"] = "options-info-members",
                      ["layout"] = {
                        ["base"] = {},
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
                            ["path"] = "options.state.accessStatus"
                          }
                        }
                      },
                      ["type"] = "control",
                      ["variant"] = "default"
                    }
                  },
                  ["id"] = "options-information-card",
                  ["layout"] = {
                    ["base"] = {
                      {
                        ["name"] = "columns",
                        ["value"] = {
                          ["kind"] = "literal",
                          ["value"] = 4
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
                              ["value"] = 2
                            }
                          }
                        },
                        ["profileId"] = "compact"
                      }
                    }
                  },
                  ["props"] = {
                    {
                      ["name"] = "title",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "options.summary.information.title"
                      }
                    },
                    {
                      ["name"] = "help",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "options.summary.information.help"
                      }
                    }
                  },
                  ["type"] = "block",
                  ["variant"] = "default"
                }
              },
              ["id"] = "options-information-host",
              ["layout"] = {
                ["base"] = {
                  {
                    ["name"] = "padding",
                    ["value"] = {
                      ["kind"] = "literal",
                      ["value"] = 0
                    }
                  }
                },
                ["mode"] = "column",
                ["overrides"] = {}
              },
              ["props"] = {
                {
                  ["name"] = "overflow",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = "clip"
                  }
                }
              },
              ["type"] = "container",
              ["variant"] = "dynamic"
            },
            {
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
                      ["id"] = "options-power-status",
                      ["layout"] = {
                        ["base"] = {},
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
                            ["path"] = "options.state.power"
                          }
                        }
                      },
                      ["type"] = "control",
                      ["variant"] = "success"
                    }
                  },
                  ["id"] = "options-energy-card",
                  ["layout"] = {
                    ["base"] = {
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
                        ["ref"] = "options.summary.energy.title"
                      }
                    },
                    {
                      ["name"] = "help",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "options.summary.energy.help"
                      }
                    }
                  },
                  ["type"] = "block",
                  ["variant"] = "default"
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
                      ["actions"] = {},
                      ["children"] = {},
                      ["id"] = "options-terminal-range",
                      ["layout"] = {
                        ["base"] = {},
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
                            ["path"] = "options.state.terminalRange"
                          }
                        }
                      },
                      ["type"] = "control",
                      ["variant"] = "default"
                    },
                    {
                      ["actions"] = {},
                      ["children"] = {},
                      ["id"] = "options-network-range",
                      ["layout"] = {
                        ["base"] = {},
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
                            ["path"] = "options.state.networkRange"
                          }
                        }
                      },
                      ["type"] = "control",
                      ["variant"] = "default"
                    },
                    {
                      ["actions"] = {},
                      ["children"] = {},
                      ["id"] = "options-antenna-range",
                      ["layout"] = {
                        ["base"] = {},
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
                            ["path"] = "options.state.antennaRange"
                          }
                        }
                      },
                      ["type"] = "control",
                      ["variant"] = "default"
                    }
                  },
                  ["id"] = "options-range-card",
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
                  ["props"] = {
                    {
                      ["name"] = "title",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "options.state.range.title"
                      }
                    },
                    {
                      ["name"] = "help",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "options.state.range.help"
                      }
                    }
                  },
                  ["type"] = "block",
                  ["variant"] = "default"
                }
              },
              ["id"] = "options-summary-cards",
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
                  },
                  {
                    ["name"] = "padding",
                    ["value"] = {
                      ["kind"] = "literal",
                      ["value"] = 0
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
              ["props"] = {
                {
                  ["name"] = "overflow",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = "clip"
                  }
                }
              },
              ["type"] = "container",
              ["variant"] = "dynamic"
            }
          },
          ["id"] = "options-summary-block",
          ["layout"] = {
            ["base"] = {
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
                ["ref"] = "options.summary.title"
              }
            },
            {
              ["name"] = "help",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "options.summary.help"
              }
            }
          },
          ["type"] = "block",
          ["variant"] = "default"
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
                    ["path"] = "options.admin.terminalHeaderActions"
                  }
                }
              }
            }
          },
          ["children"] = {
            {
              ["actions"] = {
                {
                  ["actionId"] = "options.open-terminal",
                  ["event"] = "activate"
                }
              },
              ["children"] = {},
              ["columns"] = {
                {
                  ["align"] = "left",
                  ["flex"] = 1,
                  ["key"] = "name",
                  ["labelRef"] = "options.admin.column.terminal-name",
                  ["min"] = 130
                },
                {
                  ["align"] = "left",
                  ["flex"] = 1,
                  ["key"] = "coords",
                  ["labelRef"] = "options.admin.column.coordinates",
                  ["min"] = 130
                },
                {
                  ["align"] = "left",
                  ["key"] = "role",
                  ["labelRef"] = "options.admin.column.terminal-role",
                  ["width"] = 110
                },
                {
                  ["align"] = "right",
                  ["key"] = "status",
                  ["labelRef"] = "options.admin.column.status",
                  ["width"] = 100
                }
              },
              ["id"] = "options-terminals-table",
              ["layout"] = {
                ["base"] = {},
                ["mode"] = "column",
                ["overrides"] = {}
              },
              ["props"] = {
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.admin.terminals"
                  }
                }
              },
              ["type"] = "table",
              ["variant"] = "interactive"
            }
          },
          ["id"] = "options-terminals-block",
          ["layout"] = {
            ["base"] = {
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
                ["ref"] = "options.admin.terminals.title"
              }
            },
            {
              ["name"] = "help",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "options.admin.terminals.help"
              }
            }
          },
          ["type"] = "block",
          ["variant"] = "default"
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
                    ["path"] = "options.admin.memberHeaderActions"
                  }
                }
              }
            }
          },
          ["children"] = {
            {
              ["actions"] = {
                {
                  ["actionId"] = "options.open-member",
                  ["event"] = "activate"
                }
              },
              ["children"] = {},
              ["columns"] = {
                {
                  ["align"] = "left",
                  ["key"] = "role",
                  ["labelRef"] = "options.admin.column.member-role",
                  ["width"] = 120
                },
                {
                  ["align"] = "left",
                  ["flex"] = 1,
                  ["key"] = "name",
                  ["labelRef"] = "options.admin.column.member-name",
                  ["min"] = 160
                },
                {
                  ["align"] = "right",
                  ["key"] = "connection",
                  ["labelRef"] = "options.admin.column.connection",
                  ["width"] = 140
                }
              },
              ["id"] = "options-members-table",
              ["layout"] = {
                ["base"] = {},
                ["mode"] = "column",
                ["overrides"] = {}
              },
              ["props"] = {
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.admin.members"
                  }
                }
              },
              ["type"] = "table",
              ["variant"] = "interactive"
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "options-succession-hint",
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
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.admin.succession.help"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.admin.successionHint"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "subtle",
              ["visual"] = {
                ["visibleWhen"] = "owner"
              }
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "options-backup-warning",
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
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.admin.succession.warning"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.admin.backupWarning"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "warning",
              ["visual"] = {
                ["visibleWhen"] = "owner-without-backup"
              }
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "options.claim-ownership",
                  ["event"] = "activate"
                }
              },
              ["children"] = {},
              ["id"] = "options-claim-ownership",
              ["layout"] = {
                ["base"] = {},
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
                    ["ref"] = "options.admin.claim"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.admin.canClaim"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default",
              ["visual"] = {
                ["visibleWhen"] = "can-claim-as-admin"
              }
            },
            {
              ["actions"] = {},
              ["children"] = {
                {
                  ["actions"] = {},
                  ["children"] = {},
                  ["id"] = "options-access-title",
                  ["layout"] = {
                    ["base"] = {},
                    ["mode"] = "row",
                    ["overrides"] = {}
                  },
                  ["props"] = {
                    {
                      ["name"] = "kind",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = "section-title"
                      }
                    },
                    {
                      ["name"] = "label",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "options.admin.access.title"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                },
                {
                  ["actions"] = {},
                  ["children"] = {},
                  ["id"] = "options-access-help",
                  ["layout"] = {
                    ["base"] = {},
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
                      ["name"] = "label",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "options.admin.access.help"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "subtle"
                }
              },
              ["id"] = "options-access-copy",
              ["layout"] = {
                ["base"] = {
                  {
                    ["name"] = "gap",
                    ["value"] = {
                      ["kind"] = "token",
                      ["ref"] = "spacing.4"
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
                    ["path"] = "options.admin.access"
                  }
                }
              },
              ["type"] = "form",
              ["variant"] = "plain",
              ["visual"] = {
                ["visibleWhen"] = "admin-or-owner"
              }
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "options.add-access",
                  ["event"] = "submit"
                }
              },
              ["children"] = {
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "options.select-access",
                      ["event"] = "change"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-access-subject",
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
                  ["options"] = {
                    {
                      ["id"] = "available",
                      ["labelRef"] = "options.admin.access.select",
                      ["value"] = "available"
                    }
                  },
                  ["props"] = {
                    {
                      ["name"] = "kind",
                      ["value"] = {
                        ["kind"] = "literal",
                        ["value"] = "combo"
                      }
                    },
                    {
                      ["name"] = "label",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "options.admin.access.select"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "options.admin.access.subject"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                },
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "options.add-access",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-access-add",
                  ["layout"] = {
                    ["base"] = {},
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
                        ["ref"] = "options.admin.access.add"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "field-action"
                }
              },
              ["id"] = "options-access-form",
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
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.admin.access"
                  }
                }
              },
              ["type"] = "form",
              ["variant"] = "inline",
              ["visual"] = {
                ["visibleWhen"] = "admin-or-owner"
              }
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "options-access-warning",
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
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.admin.access.empty"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "warning",
              ["visual"] = {
                ["visibleWhen"] = "add-without-selection"
              }
            }
          },
          ["id"] = "options-members-block",
          ["layout"] = {
            ["base"] = {
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
                ["ref"] = "options.admin.members.title"
              }
            },
            {
              ["name"] = "help",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "options.admin.members.help"
              }
            }
          },
          ["type"] = "block",
          ["variant"] = "default"
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
                  ["actionId"] = "options.change-palette",
                  ["event"] = "activate"
                }
              },
              ["children"] = {},
              ["id"] = "options-palette-options",
              ["layout"] = {
                ["base"] = {
                  {
                    ["name"] = "columns",
                    ["value"] = {
                      ["kind"] = "literal",
                      ["value"] = 3
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
                          ["value"] = 2
                        }
                      }
                    },
                    ["profileId"] = "compact"
                  }
                }
              },
              ["props"] = {
                {
                  ["name"] = "items",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.state.palettes"
                  }
                },
                {
                  ["name"] = "columns",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = 3
                  }
                },
                {
                  ["name"] = "maxColumns",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = 3
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
              ["variant"] = "palette"
            }
          },
          ["id"] = "options-palette-block",
          ["layout"] = {
            ["base"] = {
              {
                ["name"] = "span",
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
            ["mode"] = "column",
            ["overrides"] = {}
          },
          ["props"] = {
            {
              ["name"] = "title",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "options.state.palette.title"
              }
            },
            {
              ["name"] = "help",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "options.state.palette.help"
              }
            }
          },
          ["type"] = "block",
          ["variant"] = "default"
        }
      },
      ["id"] = "options-root",
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
      ["variant"] = "fill"
    }
  },
  ["surfaceReferences"] = {},
  ["tokens"] = {
    {
      ["id"] = "spacing.4",
      ["kind"] = "number",
      ["runtime"] = true,
      ["value"] = 4
    },
    {
      ["id"] = "spacing.8",
      ["kind"] = "number",
      ["runtime"] = true,
      ["value"] = 8
    }
  }
}
