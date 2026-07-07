[
  layers: [
    web: "SmolsqlsWeb.*",
    data_plane: "Smolsqls.DataPlane.*",
    control_plane: "Smolsqls.ControlPlane.*",
    read_model: "Smolsqls.ReadModel.*"
  ],
  deps: [
    forbidden: [
      {:data_plane, :web},
      {:control_plane, :web},
      {:read_model, :web}
    ]
  ],
  calls: [
    forbidden: [
      {"Smolsqls.*", ["String.to_atom"]},
      {"SmolsqlsWeb.*", ["String.to_atom"]}
    ]
  ]
]
