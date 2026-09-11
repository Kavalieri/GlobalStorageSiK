-- Generated data only. Do not edit.
return {
  ["actionAllowlist"] = {
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "warehouse.auto-sort"
    },
    {
      ["events"] = {
        "activate",
        "submit"
      },
      ["id"] = "warehouse.search"
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "warehouse.search-change"
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "warehouse.filter-family"
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "warehouse.filter-group"
    },
    {
      ["events"] = {
        "change"
      },
      ["id"] = "warehouse.filter-detail"
    },
    {
      ["events"] = {
        "activate"
      },
      ["id"] = "warehouse.row-activate"
    }
  },
  ["assets"] = {},
  ["capabilities"] = {
    "table.expandable",
    "table.pagination",
    "table.row-interactions",
    "block.header"
  },
  ["componentFactories"] = {
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
      ["id"] = "warehouse.title",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Inventario de red"
        }
      }
    },
    {
      ["id"] = "warehouse.help",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Consulta y transfiere el inventario agregado de la red. Las filas padre agrupan unidades equivalentes y se despliegan para elegir variantes o copias exactas."
        }
      }
    },
    {
      ["id"] = "warehouse.search.label",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Buscar ítem..."
        }
      }
    },
    {
      ["id"] = "warehouse.search.action",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Buscar"
        }
      }
    },
    {
      ["id"] = "warehouse.filter.family",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Familia"
        }
      }
    },
    {
      ["id"] = "warehouse.filter.group",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Grupo"
        }
      }
    },
    {
      ["id"] = "warehouse.filter.detail",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Detalle"
        }
      }
    },
    {
      ["id"] = "warehouse.option.family.all",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Familia | Todas"
        }
      }
    },
    {
      ["id"] = "warehouse.option.family.food",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Comida y bebida"
        }
      }
    },
    {
      ["id"] = "warehouse.option.family.vehicles",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Vehículos"
        }
      }
    },
    {
      ["id"] = "warehouse.option.family.containers",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Contenedores"
        }
      }
    },
    {
      ["id"] = "warehouse.option.family.knowledge",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Conocimiento y medios"
        }
      }
    },
    {
      ["id"] = "warehouse.option.family.materials",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Materiales"
        }
      }
    },
    {
      ["id"] = "warehouse.option.family.misc",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Sin clasificar"
        }
      }
    },
    {
      ["id"] = "warehouse.option.group.all",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Grupo | Todos"
        }
      }
    },
    {
      ["id"] = "warehouse.option.group.nonperishable",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "No perecedero"
        }
      }
    },
    {
      ["id"] = "warehouse.option.group.consumables",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Consumibles"
        }
      }
    },
    {
      ["id"] = "warehouse.option.group.media",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Medios grabados"
        }
      }
    },
    {
      ["id"] = "warehouse.option.group.component",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Componente"
        }
      }
    },
    {
      ["id"] = "warehouse.option.detail.all",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Detalle | Todos"
        }
      }
    },
    {
      ["id"] = "warehouse.option.detail.otherfood",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Otros alimentos"
        }
      }
    },
    {
      ["id"] = "warehouse.option.detail.fuel",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Combustible"
        }
      }
    },
    {
      ["id"] = "warehouse.option.detail.fixing",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Fijación"
        }
      }
    },
    {
      ["id"] = "warehouse.column.name",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Nombre"
        }
      }
    },
    {
      ["id"] = "warehouse.column.category",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Categoría"
        }
      }
    },
    {
      ["id"] = "warehouse.column.zone",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Zona"
        }
      }
    },
    {
      ["id"] = "warehouse.column.count",
      ["translations"] = {
        {
          ["locale"] = "es",
          ["text"] = "Cant."
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
    ["surfaceSpecSha256"] = "708950af13c364bee102b6cd1c6b3a6e9adf49f7189536871d437bc19ffa80a2",
    ["visualCanonicalizer"] = "sik-ui-dom-v2",
    ["visualMasterSha256"] = "a314f1cfc3782d23d54e36f2c19a202cb3d0294fcc036586d2ded75bb2dd276a",
    ["visualSubtreeSha256"] = "3fec3f554d178211ec9c77ef1f0b7779635cdc81686c9152f25409de8413ac79"
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
    ["id"] = "tab-warehouse",
    ["kind"] = "embedded",
    ["owner"] = {
      ["modulePath"] = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua",
      ["repository"] = "global-storage-sik",
      ["symbol"] = "GlobalStorageSiK.TerminalItems"
    },
    ["profiles"] = {
      "compact",
      "standard",
      "wide"
    },
    ["root"] = {
      ["actions"] = {
        {
          ["actionId"] = "warehouse.auto-sort",
          ["event"] = "activate"
        }
      },
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
                ["path"] = "warehouse.headerActions"
              }
            }
          }
        }
      },
      ["children"] = {
        {
          ["actions"] = {},
          ["children"] = {},
          ["id"] = "warehouse-capacity",
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
                ["value"] = "progress"
              }
            },
            {
              ["name"] = "data",
              ["value"] = {
                ["kind"] = "data",
                ["path"] = "warehouse.capacity"
              }
            }
          },
          ["type"] = "control",
          ["variant"] = "capacity"
        },
        {
          ["actions"] = {},
          ["children"] = {
            {
              ["actions"] = {
                {
                  ["actionId"] = "warehouse.search-change",
                  ["event"] = "change"
                },
                {
                  ["actionId"] = "warehouse.search",
                  ["event"] = "submit"
                }
              },
              ["children"] = {},
              ["id"] = "warehouse-search-field",
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
                    ["value"] = "search"
                  }
                },
                {
                  ["name"] = "label",
                  ["value"] = {
                    ["kind"] = "i18n",
                    ["ref"] = "warehouse.search.label"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "warehouse.search.query"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default"
            }
          },
          ["id"] = "warehouse-search-form",
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
          ["props"] = {
            {
              ["name"] = "data",
              ["value"] = {
                ["kind"] = "data",
                ["path"] = "warehouse.search"
              }
            }
          },
          ["type"] = "form",
          ["variant"] = "inline"
        },
        {
          ["actions"] = {},
          ["children"] = {
            {
              ["actions"] = {
                {
                  ["actionId"] = "warehouse.filter-family",
                  ["event"] = "change"
                }
              },
              ["children"] = {},
              ["id"] = "warehouse-family-filter",
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
                  ["id"] = "all",
                  ["labelRef"] = "warehouse.option.family.all",
                  ["value"] = "all"
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
                    ["ref"] = "warehouse.filter.family"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "warehouse.filters.family"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default"
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "warehouse.filter-group",
                  ["event"] = "change"
                }
              },
              ["children"] = {},
              ["id"] = "warehouse-group-filter",
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
                  ["id"] = "all",
                  ["labelRef"] = "warehouse.option.group.all",
                  ["value"] = "all"
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
                    ["ref"] = "warehouse.filter.group"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "warehouse.filters.group"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default"
            },
            {
              ["actions"] = {
                {
                  ["actionId"] = "warehouse.filter-detail",
                  ["event"] = "change"
                }
              },
              ["children"] = {},
              ["id"] = "warehouse-detail-filter",
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
                  ["id"] = "all",
                  ["labelRef"] = "warehouse.option.detail.all",
                  ["value"] = "all"
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
                    ["ref"] = "warehouse.filter.detail"
                  }
                },
                {
                  ["name"] = "data",
                  ["value"] = {
                    ["kind"] = "data",
                    ["path"] = "warehouse.filters.detail"
                  }
                }
              },
              ["type"] = "control",
              ["variant"] = "default"
            }
          },
          ["id"] = "warehouse-filter-form",
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
                ["path"] = "warehouse.filters"
              }
            }
          },
          ["type"] = "form",
          ["variant"] = "inline"
        },
        {
          ["actions"] = {
            {
              ["actionId"] = "warehouse.row-activate",
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
                    ["value"] = true
                  }
                }
              }
            },
            {
              ["id"] = "table.pagination",
              ["props"] = {
                {
                  ["name"] = "page-size",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = 15
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
                    ["value"] = true
                  }
                },
                {
                  ["name"] = "drag",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = true
                  }
                },
                {
                  ["name"] = "preserveVanillaTooltip",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = true
                  }
                },
                {
                  ["name"] = "exactSelection",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = true
                  }
                },
                {
                  ["name"] = "dragGhostMode",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = "visible-rows"
                  }
                },
                {
                  ["name"] = "transferScope",
                  ["value"] = {
                    ["kind"] = "literal",
                    ["value"] = "logical-selection"
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
              ["labelRef"] = "warehouse.column.name",
              ["min"] = 130
            },
            {
              ["align"] = "left",
              ["flex"] = 1.4,
              ["key"] = "category",
              ["labelRef"] = "warehouse.column.category",
              ["min"] = 180
            },
            {
              ["align"] = "left",
              ["key"] = "zone",
              ["labelRef"] = "warehouse.column.zone",
              ["width"] = 110
            },
            {
              ["align"] = "right",
              ["key"] = "count",
              ["labelRef"] = "warehouse.column.count",
              ["width"] = 70
            }
          },
          ["id"] = "warehouse-table",
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
                ["path"] = "warehouse.rows"
              }
            }
          },
          ["type"] = "table",
          ["variant"] = "inventory"
        }
      },
      ["id"] = "warehouse-root",
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
            ["ref"] = "warehouse.title"
          }
        },
        {
          ["name"] = "help",
          ["value"] = {
            ["kind"] = "i18n",
            ["ref"] = "warehouse.help"
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
      ["state"] = {
        ["default"] = "warehouse-list",
        ["options"] = {
          "warehouse-list",
          "warehouse-drop"
        },
        ["views"] = {
          {
            ["contentId"] = "warehouse-table",
            ["values"] = {
              "warehouse-list",
              "warehouse-drop"
            }
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
