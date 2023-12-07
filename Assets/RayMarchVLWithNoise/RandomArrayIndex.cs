using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Random = UnityEngine.Random;

[ExecuteInEditMode]
public class RandomArrayIndex : MonoBehaviour
{
    private const int s_MaxSliceCount = 256;
    [Range(0, s_MaxSliceCount)] public int index = 0;

    private void OnValidate()
    {
        index = (int)Random.value * 256;
        List<Vector3> uvs = new List<Vector3>();
        Mesh mesh = this.GetComponent<MeshFilter>().mesh;
        mesh.GetUVs(0, uvs);
        for (int i = 0; i < uvs.Count; i++)
        {
            uvs[i] = new Vector3(uvs[i].x, uvs[i].y, index);
        }
        mesh.SetUVs(channel:0, uvs:uvs);
    }

    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }
}
