from __future__ import annotations

from typing import Final


CATEGORY_NAMES_ZH: Final[dict[str, str]] = {
    "alpha_diversity": "Alpha 多样性",
    "beta_diversity": "Beta 多样性与排序",
    "composition": "群落组成与可视化",
    "differential_abundance": "差异丰度",
    "biomarker_ml": "机器学习与生物标志物",
    "network": "共现网络",
    "community_assembly": "群落组装与来源",
    "functional_prediction": "功能预测",
    "other": "其他分析",
}

BASELINE_METHOD_NAMES_ZH: Final[dict[str, str]] = {
    "qc": "数据质量控制（QC）",
    "alpha": "Alpha 多样性分析",
    "beta": "Beta 多样性分析",
    "composition": "群落组成分析",
}


# 这是用户界面使用的方法目录。键是稳定的内部调用 ID，值是生物学用户
# 能理解的方法名称和用途。新增 R 函数时应同时在这里补充说明。
FUNCTION_PRESENTATIONS: Final[dict[str, dict[str, str]]] = {
    "cir-barplot-micro": {
        "display_name": "环形物种组成柱状图",
        "description": "用环形堆叠柱展示不同样本或分组的主要分类单元相对丰度。",
    },
    "cir-plot-micro": {
        "display_name": "分类组成圈图",
        "description": "在环形布局中展示分类层级及其丰度关系。",
    },
    "clumicro-bar-micro": {
        "display_name": "聚类物种组成柱状图",
        "description": "按群落组成相似性聚类样本，并同步展示主要物种丰度。",
    },
    "cluster-micro": {
        "display_name": "样本层次聚类",
        "description": "基于群落距离对样本进行层次聚类，观察样本聚集模式。",
    },
    "distance-micro": {
        "display_name": "样本距离分析",
        "description": "计算样本间群落距离，用于衡量群落组成差异。",
    },
    "ggflower-micro": {
        "display_name": "花瓣图（共有与特有特征）",
        "description": "展示多个分组之间共有及各组特有的 ASV/OTU。",
    },
    "ggven-upset-micro": {
        "display_name": "UpSet 集合分析",
        "description": "在分组较多时展示 ASV/OTU 集合的交集规模。",
    },
    "mantal-micro": {
        "display_name": "Mantel 关联分析",
        "description": "检验群落距离矩阵与环境或表型距离矩阵之间的相关性。",
    },
    "maptree-micro": {
        "display_name": "分类层级树图",
        "description": "以树状结构展示主要微生物类群的分类层级和丰度。",
    },
    "ordinate-micro": {
        "display_name": "群落排序分析",
        "description": "通过降维排序展示样本间群落组成差异及分组趋势。",
    },
    "sankey-m-group-micro": {
        "display_name": "分组分类桑基图",
        "description": "展示各分组从高到低分类层级的组成流向。",
    },
    "sankey-micro": {
        "display_name": "样本分类桑基图",
        "description": "展示各样本在不同分类层级之间的组成流向。",
    },
    "script-aldex2": {
        "display_name": "ALDEx2 差异丰度分析",
        "description": "基于组成数据变换识别组间差异分类单元。",
    },
    "script-alpha": {
        "display_name": "Alpha 多样性分析",
        "description": "计算 Observed、Shannon、Simpson 等样本内多样性指标。",
    },
    "script-alpha-pd": {
        "display_name": "Faith's PD 系统发育多样性",
        "description": "结合系统发育树评估样本内的系统发育多样性。",
    },
    "script-alpha-rarefaction": {
        "display_name": "Alpha 多样性稀释曲线",
        "description": "观察不同抽样深度下 Alpha 多样性指标是否趋于稳定。",
    },
    "script-ancombc2": {
        "display_name": "ANCOM-BC2 差异丰度分析",
        "description": "校正测序组成偏差后检验分类单元的组间差异。",
    },
    "script-bagging": {
        "display_name": "Bagging 集成分类",
        "description": "训练装袋集成分类器并评估候选微生物标志物。",
    },
    "script-barplot": {
        "display_name": "物种组成柱状图",
        "description": "展示样本或分组中主要分类单元的相对丰度。",
    },
    "script-bnti": {
        "display_name": "βNTI 群落组装分析",
        "description": "基于系统发育周转判断选择作用对群落组装的影响。",
    },
    "script-bnti-rcbray": {
        "display_name": "βNTI + RCbray 组装过程分析",
        "description": "联合系统发育与物种周转指标区分主要群落组装过程。",
    },
    "script-breakaway": {
        "display_name": "breakaway 丰富度估计",
        "description": "估计未观测物种并给出更稳健的群落丰富度及不确定性。",
    },
    "script-coda-pca": {
        "display_name": "组成数据 PCA（CoDA-PCA）",
        "description": "对丰度表进行组成数据变换后开展主成分分析。",
    },
    "script-corncob": {
        "display_name": "corncob 差异丰度分析",
        "description": "使用 Beta-binomial 模型检验丰度和离散度差异。",
    },
    "script-decision-tree": {
        "display_name": "决策树分类",
        "description": "构建可解释的树模型并筛选区分分组的候选特征。",
    },
    "script-deseq2": {
        "display_name": "DESeq2 差异丰度分析",
        "description": "使用负二项模型识别组间差异分类单元。",
    },
    "script-edger": {
        "display_name": "edgeR 差异丰度分析",
        "description": "使用负二项广义线性模型检验分类单元丰度差异。",
    },
    "script-feast": {
        "display_name": "FEAST 微生物来源追踪",
        "description": "估计各潜在来源对目标微生物群落的贡献比例。",
    },
    "script-function-bubble": {
        "display_name": "预测功能气泡图",
        "description": "以气泡图汇总主要预测功能的丰度与分组差异。",
    },
    "script-function-diff": {
        "display_name": "预测功能差异分析",
        "description": "比较不同分组之间预测 KO 功能的丰度差异。",
    },
    "script-gunifrac": {
        "display_name": "Generalized UniFrac 距离分析",
        "description": "结合系统发育树计算兼顾高、低丰度类群的群落距离。",
    },
    "script-heatmap": {
        "display_name": "物种丰度热图",
        "description": "用热图展示主要分类单元在样本或分组中的丰度模式。",
    },
    "script-kegg-enrich": {
        "display_name": "KEGG 通路富集分析",
        "description": "检验差异预测功能在 KEGG 通路中的富集情况。",
    },
    "script-lasso": {
        "display_name": "LASSO 特征筛选",
        "description": "通过正则化回归筛选能够区分分组的候选特征。",
    },
    "script-lda": {
        "display_name": "线性判别分析（LDA）",
        "description": "寻找能够最大化分组区分度的特征组合。",
    },
    "script-lefse": {
        "display_name": "LEfSe 生物标志物分析",
        "description": "结合非参数检验与 LDA 效应量识别组间标志物。",
    },
    "script-linda": {
        "display_name": "LinDA 差异丰度分析",
        "description": "基于线性模型和组成偏差校正检验分类单元差异。",
    },
    "script-loading-pca": {
        "display_name": "PCA 载荷分析",
        "description": "识别对主成分分离贡献较大的微生物特征。",
    },
    "script-maaslin2": {
        "display_name": "MaAsLin2 多变量关联分析",
        "description": "用多变量线性模型分析微生物特征与元数据的关联。",
    },
    "script-maaslin3": {
        "display_name": "MaAsLin3 多变量关联分析",
        "description": "联合评估微生物特征的丰度和出现概率与元数据的关联。",
    },
    "script-manhattan": {
        "display_name": "差异特征曼哈顿图",
        "description": "按分类层级集中展示大量差异特征的显著性和方向。",
    },
    "script-metagenomeseq": {
        "display_name": "metagenomeSeq 差异丰度分析",
        "description": "使用零膨胀模型识别稀疏微生物数据中的组间差异。",
    },
    "script-microtest": {
        "display_name": "群落结构整体差异检验",
        "description": "使用 PERMANOVA、ANOSIM 或 MRPP 检验分组间群落差异。",
    },
    "script-naive-bayes": {
        "display_name": "朴素贝叶斯分类",
        "description": "训练概率分类模型并评估候选微生物标志物。",
    },
    "script-network": {
        "display_name": "微生物共现网络",
        "description": "根据特征间关联构建并可视化微生物共现网络。",
    },
    "script-network-compare": {
        "display_name": "分组网络差异比较",
        "description": "比较不同处理组网络的连接结构及差异关联。",
    },
    "script-network-compositional": {
        "display_name": "组成数据关联网络",
        "description": "经组成数据变换后估计微生物特征之间的稳健关联。",
    },
    "script-network-properties": {
        "display_name": "网络拓扑性质分析",
        "description": "计算节点度、模块化、聚类系数等网络拓扑指标。",
    },
    "script-network-robustness": {
        "display_name": "网络鲁棒性分析",
        "description": "模拟节点移除，评估微生物网络抵抗扰动的能力。",
    },
    "script-network-stability": {
        "display_name": "网络稳定性分析",
        "description": "评估网络结构及关键节点在重采样下的稳定程度。",
    },
    "script-neutral-model": {
        "display_name": "中性群落模型",
        "description": "评估随机扩散和生态漂变对物种出现频率的解释程度。",
    },
    "script-nnet": {
        "display_name": "神经网络分类",
        "description": "训练浅层神经网络并评估分组预测与候选标志物。",
    },
    "script-nullmodel": {
        "display_name": "群落零模型分析",
        "description": "通过随机化检验群落格局是否偏离随机组装预期。",
    },
    "script-pair-microtest": {
        "display_name": "群落结构两两差异检验",
        "description": "对多个分组进行成对的群落结构差异检验。",
    },
    "script-pca": {
        "display_name": "主成分分析（PCA）",
        "description": "通过线性降维展示样本总体差异及主要变化方向。",
    },
    "script-random-forest": {
        "display_name": "随机森林分类",
        "description": "构建随机森林分类器并排序候选微生物标志物。",
    },
    "script-rarefaction": {
        "display_name": "测序深度稀释分析",
        "description": "评估测序深度对检出特征数和群落覆盖度的影响。",
    },
    "script-rcbray": {
        "display_name": "RCbray 群落组装分析",
        "description": "基于 Bray-Curtis 随机化区分扩散限制和均质扩散等过程。",
    },
    "script-rfcv": {
        "display_name": "随机森林交叉验证筛选",
        "description": "通过交叉验证确定具有较好预测能力的特征数量。",
    },
    "script-roc": {
        "display_name": "ROC 诊断效能分析",
        "description": "用 ROC 曲线和 AUC 评估候选标志物的区分能力。",
    },
    "script-siamcat": {
        "display_name": "SIAMCAT 微生物组分类",
        "description": "采用标准化机器学习流程训练并评估微生物组分类模型。",
    },
    "script-spieceasi": {
        "display_name": "SPIEC-EASI 稀疏网络",
        "description": "针对组成型微生物数据推断稀疏条件依赖网络。",
    },
    "script-splsda": {
        "display_name": "稀疏偏最小二乘判别分析（sPLS-DA）",
        "description": "同时完成监督降维、分组判别和特征筛选。",
    },
    "script-stamp": {
        "display_name": "STAMP 风格差异比较",
        "description": "展示组间丰度差异、效应量及置信区间。",
    },
    "script-svm": {
        "display_name": "支持向量机分类（SVM）",
        "description": "训练支持向量机并评估分组预测和候选标志物。",
    },
    "script-ternary": {
        "display_name": "三元相图",
        "description": "比较三个分组中分类单元的相对偏好和分布。",
    },
    "script-venn": {
        "display_name": "Venn 共有与特有分析",
        "description": "展示少量分组之间共有及特有的 ASV/OTU。",
    },
    "script-volcano": {
        "display_name": "差异丰度火山图",
        "description": "综合效应大小和显著性展示差异分类单元。",
    },
    "script-volcano-specific": {
        "display_name": "特异差异特征火山图",
        "description": "突出展示指定比较中具有方向性的显著差异特征。",
    },
    "script-wgcna": {
        "display_name": "WGCNA 共丰度模块分析",
        "description": "识别协同变化的微生物模块并关联样本表型。",
    },
    "ven-network-micro": {
        "display_name": "共有与特有特征网络图",
        "description": "用网络形式展示分组与共有或特有 ASV/OTU 的关系。",
    },
    "vensuper-micro": {
        "display_name": "SuperVenn 多集合分析",
        "description": "在分组较多时概览 ASV/OTU 集合之间的重叠关系。",
    },
}


def presentation(function_id: str, category: str) -> dict[str, str]:
    configured = FUNCTION_PRESENTATIONS.get(function_id)
    if configured is not None:
        return dict(configured)
    return {
        "display_name": "待命名分析方法",
        "description": f"此 {CATEGORY_NAMES_ZH.get(category, '扩展')} 方法尚未配置用户说明。",
    }


def method_name(function_id: str, category: str = "other") -> str:
    if function_id in BASELINE_METHOD_NAMES_ZH:
        return BASELINE_METHOD_NAMES_ZH[function_id]
    return presentation(function_id, category)["display_name"]
