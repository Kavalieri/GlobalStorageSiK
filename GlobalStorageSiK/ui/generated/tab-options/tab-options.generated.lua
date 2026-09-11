-- Generated data only. Do not edit.
return {
  ["actionAllowlist"] = {
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
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "options.taxonomy.type"
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "options.taxonomy.reason"
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "options.taxonomy.choice1"
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "options.taxonomy.choice2"
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "options.taxonomy.choice3"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "options.taxonomy.consult"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "options.taxonomy.apply"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "options.taxonomy.restore"
    },
    {
      ["events"] = {
        "change",
        "submit"
      },
      ["id"] = "options.change-opacity"
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
    ["manifestSha256"] = "2cca88b2efa1f44f02bae6d86aef44131bbd212a002c9b439c6d5d673505b063",
    ["manifestVersion"] = "0.1.0-preview",
    ["namespace"] = "SiK.UI"
  },
  ["i18n"] = {
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
          ["text"] = "Si mueres, la red queda vacante. Un miembro con acceso puede reclamarla."
        }
      }
    },
    {
      ["id"] = "options.admin.succession.warning",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Sin otros miembros: si mueres, esta red se quedará sin propietario."
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
    },
    {
      ["id"] = "options.admin.succession.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Sucesión de la red"
        }
      }
    },
    {
      ["id"] = "options.admin.succession.header-help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "La sucesión conserva una vía de recuperación para la red si muere su propietario actual."
        }
      }
    },
    {
      ["id"] = "options.admin.succession.no-backup-help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "No hay otro miembro que pueda reclamar la red si fallece el propietario."
        }
      }
    },
    {
      ["id"] = "options.taxonomy.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Correcciones de este mundo"
        }
      }
    },
    {
      ["id"] = "options.taxonomy.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Corrige la clasificación de los objetos en toda esta partida, independientemente de la red. Restaurar recupera la clasificación automática. El motivo se conserva en el registro privado."
        }
      }
    },
    {
      ["id"] = "options.taxonomy.type",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Tipo de objeto"
        }
      }
    },
    {
      ["id"] = "options.taxonomy.choice",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Nueva clasificación"
        }
      }
    },
    {
      ["id"] = "options.taxonomy.reason",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Motivo"
        }
      }
    },
    {
      ["id"] = "options.taxonomy.consult",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Consultar"
        }
      }
    },
    {
      ["id"] = "options.taxonomy.apply",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Aplicar corrección"
        }
      }
    },
    {
      ["id"] = "options.taxonomy.restore",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Restaurar automática"
        }
      }
    },
    {
      ["id"] = "options.state.opacity.label",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Opacidad de ventanas (%)"
        }
      }
    },
    {
      ["id"] = "options.state.opacity.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "45 % más translúcido · 80 % apariencia aprobada · 100 % opaco. Se aplica a todas las ventanas de este personaje; no cambia la red."
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
    ["frameworkManifestSha256"] = "2cca88b2efa1f44f02bae6d86aef44131bbd212a002c9b439c6d5d673505b063",
    ["generatorSha256"] = "b680dfefc17e687bb2839cb5f589d64cf0da07fff454a4ee26e002333eee73ae",
    ["schemaSha256"] = "ef8b4a9769c8794563d33ee8fabc8f407504300a36094e1689f0e300286695e5",
    ["surfaceSpecSha256"] = "4c41e6074d96164806cf1870ee7cd886299794953f819650c28514adf3b49046",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "a314f1cfc3782d23d54e36f2c19a202cb3d0294fcc036586d2ded75bb2dd276a",
    ["visualSubtreeSha256"] = "5a822281a8b7fed7ea0cb5f6680f56a404395934c3bdf602951483a796edd1dc"
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
                    ["value"] = "alert-row"
                  }
                },
                {
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.admin.succession.title"
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
                ["visibleWhen"] = "owner-with-backup"
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
                    ["value"] = "alert-row"
                  }
                },
                {
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.admin.succession.title"
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
              ["variant"] = "subtle",
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
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "options.admin.accessActions"
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
                  },
                  {
                    ["name"] = "stack-below",
                    ["value"] = {
                      ["kind"] = "literal",
                      ["value"] = 560
                    }
                  }
                },
                ["mode"] = "row",
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
              ["variant"] = "inline",
              ["visual"] = {
                ["visibleWhen"] = "admin-or-owner"
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
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "options-taxonomy-type-label",
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
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.taxonomy.type"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.taxonomy.labelStyle"
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
                      ["actionId"] = "options.taxonomy.type",
                      ["event"] = "change"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-taxonomy-type",
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
                        ["value"] = "field"
                      }
                    },
                    {
                      ["name"] = "label",
                      ["value"] = {
                        ["kind"] = "i18n",
                        ["ref"] = "options.taxonomy.type"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "options.taxonomy.fullType"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                },
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "options.taxonomy.consult",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-taxonomy-consult",
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
                        ["ref"] = "options.taxonomy.consult"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "options.taxonomy.consult"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "field-action"
                }
              },
              ["id"] = "options-taxonomy-lookup-row",
              ["layout"] = {
                ["base"] = {
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
                ["mode"] = "row",
                ["overrides"] = {}
              },
              ["props"] = {},
              ["type"] = "container",
              ["variant"] = "fill"
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "options-taxonomy-current",
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
                    ["path"] = "options.taxonomy.current"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default"
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "options-taxonomy-choice-label",
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
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.taxonomy.choice"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.taxonomy.labelStyle"
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
                      ["actionId"] = "options.taxonomy.choice1",
                      ["event"] = "change"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-taxonomy-choice1",
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
                        ["value"] = "combo"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "options.taxonomy.choice1"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                },
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "options.taxonomy.choice2",
                      ["event"] = "change"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-taxonomy-choice2",
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
                        ["value"] = "combo"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "options.taxonomy.choice2"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                },
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "options.taxonomy.choice3",
                      ["event"] = "change"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-taxonomy-choice3",
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
                        ["value"] = "combo"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "options.taxonomy.choice3"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                }
              },
              ["id"] = "options-taxonomy-choices",
              ["layout"] = {
                ["base"] = {
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
                ["mode"] = "row",
                ["overrides"] = {}
              },
              ["props"] = {},
              ["type"] = "container",
              ["variant"] = "fill"
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "options-taxonomy-reason-label",
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
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.taxonomy.reason"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.taxonomy.labelStyle"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default"
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "options.taxonomy.reason",
                  ["event"] = "change"
                }
              },
              ["children"] = {},
              ["id"] = "options-taxonomy-reason",
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
                    ["value"] = "field"
                  }
                },
                {
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.taxonomy.reason"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.taxonomy.reason"
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
                      ["actionId"] = "options.taxonomy.apply",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-taxonomy-apply",
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
                        ["ref"] = "options.taxonomy.apply"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "options.taxonomy.apply"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                },
                {
                  ["actions"] = {
                    {
                      ["actionId"] = "options.taxonomy.restore",
                      ["event"] = "activate"
                    }
                  },
                  ["children"] = {},
                  ["id"] = "options-taxonomy-restore",
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
                        ["ref"] = "options.taxonomy.restore"
                      }
                    },
                    {
                      ["name"] = "data",
                      ["value"] = {
                        ["kind"] = "data",
                        ["path"] = "options.taxonomy.restore"
                      }
                    }
                  },
                  ["type"] = "control",
                  ["variant"] = "default"
                }
              },
              ["id"] = "options-taxonomy-actions",
              ["layout"] = {
                ["base"] = {
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
                ["mode"] = "row",
                ["overrides"] = {}
              },
              ["props"] = {},
              ["type"] = "container",
              ["variant"] = "fill"
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "options-taxonomy-feedback",
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
                    ["path"] = "options.taxonomy.feedback"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default"
            }
          },
          ["id"] = "options-world-taxonomy-block",
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
                ["ref"] = "options.taxonomy.title"
              }
            },
            {
              ["name"] = "help",
              ["value"] = {
                ["kind"] = "i18n",
                ["ref"] = "options.taxonomy.help"
              }
            }
          },
          ["type"] = "block",
          ["variant"] = "default",
          ["visual"] = {
            ["visibleWhen"] = "singleplayer"
          }
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
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "options.change-opacity",
                  ["event"] = "change"
                },
                {
                  ["actionId"] = "options.change-opacity",
                  ["event"] = "submit"
                }
              },
              ["children"] = {},
              ["id"] = "options-opacity-field",
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
                    ["value"] = "field"
                  }
                },
                {
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "options.state.opacity.label"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "options.state.opacityControl"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default"
            },
            {
              ["actions"] = {},
              ["children"] = {},
              ["id"] = "options-opacity-help",
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
                    ["ref"] = "options.state.opacity.help"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "subtle"
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
